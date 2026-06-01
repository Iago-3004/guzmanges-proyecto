package com.guzmanges.api.service;

import java.time.LocalDateTime;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.guzmanges.api.dto.ClienteResponse;
import com.guzmanges.api.dto.CrearClienteRequest;
import com.guzmanges.api.entity.Cliente;
import com.guzmanges.api.entity.EstadoSync;
import com.guzmanges.api.entity.Usuario;
import com.guzmanges.api.exception.CifDuplicadoException;
import com.guzmanges.api.exception.ResourceNotFoundException;
import com.guzmanges.api.mapper.ClienteMapper;
import com.guzmanges.api.odoo.service.OdooSyncService;
import com.guzmanges.api.repository.ClienteRepository;
import com.guzmanges.api.repository.CondicionPagoRepository;
import com.guzmanges.api.repository.ModoPagoRepository;
import com.guzmanges.api.repository.UsuarioRepository;

import lombok.RequiredArgsConstructor;

/**
 * Lógica de negocio de los clientes: consulta de la cartera y alta de nuevos clientes.
 * Las altas se intentan enviar inmediatamente a Odoo; si falla, quedan PENDENTE
 * y el scheduler periódico las reintentará.
 */
@Service
@RequiredArgsConstructor
public class ClienteService {

    private static final Logger log = LoggerFactory.getLogger(ClienteService.class);

    private final ClienteRepository clienteRepository;
    private final ModoPagoRepository modoPagoRepository;
    private final CondicionPagoRepository condicionPagoRepository;
    private final UsuarioRepository usuarioRepository;
    private final ClienteMapper clienteMapper;
    private final OdooSyncService odooSyncService;

    /**
     * Lista los clientes activos, ordenados por nombre comercial.
     *
     * @return lista de clientes
     */
    @Transactional(readOnly = true)
    public List<ClienteResponse> listar() {
        return clienteRepository.findByActivoTrueOrderByNombreComercialAsc().stream()
                .map(clienteMapper::toResponse)
                .toList();
    }

    /**
     * Lista los clientes (activos e inactivos) modificados desde la fecha indicada,
     * ordenados por nombre comercial. Pensado para sincronizaciones incrementales:
     * incluye los desactivados para que la app refleje las bajas.
     *
     * @param modificadoDesde fecha de modificación mínima (inclusiva)
     * @return lista de clientes modificados a partir de esa fecha
     */
    @Transactional(readOnly = true)
    public List<ClienteResponse> listarModificadosDesde(LocalDateTime modificadoDesde) {
        return clienteRepository
                .findByFechaModificacionGreaterThanEqualOrderByNombreComercialAsc(modificadoDesde)
                .stream()
                .map(clienteMapper::toResponse)
                .toList();
    }

    /**
     * Obtiene un cliente por su identificador.
     *
     * @param id identificador del cliente
     * @return el cliente encontrado
     * @throws ResourceNotFoundException si no existe
     */
    @Transactional(readOnly = true)
    public ClienteResponse obtenerPorId(Long id) {
        Cliente cliente = clienteRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Cliente no encontrado: " + id));
        return clienteMapper.toResponse(cliente);
    }

    /**
     * Da de alta un nuevo cliente. Queda asignado al preventa que lo crea y pendiente
     * de envío a Odoo (estadoSync = PENDENTE, sin idOdoo todavía).
     *
     * Si ya existe algún cliente con el mismo CIF y no se fuerza el alta, se lanza
     * {@link CifDuplicadoException} con la lista de coincidencias, para que la app avise
     * al usuario y este decida si crear uno nuevo de todas formas.
     *
     * @param request    datos del nuevo cliente
     * @param username   nombre de usuario del preventa autenticado
     * @param forzarAlta si es true, crea el cliente aunque el CIF ya exista
     * @return el cliente creado
     */
    @Transactional
    public ClienteResponse crear(CrearClienteRequest request, String username, boolean forzarAlta) {
        if (!forzarAlta) {
            List<Cliente> existentes = clienteRepository.findByCifIgnoreCase(request.cif());
            if (!existentes.isEmpty()) {
                List<ClienteResponse> coincidencias = existentes.stream()
                        .map(clienteMapper::toResponse)
                        .toList();
                throw new CifDuplicadoException(
                        "Ya existe(n) " + existentes.size() + " cliente(s) con el CIF " + request.cif(),
                        coincidencias);
            }
        }

        Usuario comercial = usuarioRepository.findByNombreUsuario(username)
                .orElseThrow(() -> new ResourceNotFoundException("Usuario no encontrado: " + username));

        Cliente cliente = new Cliente();
        cliente.setNombreComercial(request.nombreComercial());
        cliente.setRazonSocial(request.razonSocial());
        cliente.setCif(request.cif());
        cliente.setDireccion(request.direccion());
        cliente.setLocalidad(request.localidad());
        cliente.setCodigoPostal(request.codigoPostal());
        cliente.setProvincia(request.provincia());
        cliente.setTelefono(request.telefono());
        cliente.setMovil(request.movil());
        cliente.setEmail(request.email());

        if (request.modoPagoId() != null) {
            cliente.setModoPago(modoPagoRepository.findById(request.modoPagoId())
                    .orElseThrow(() -> new ResourceNotFoundException("Modo de pago no encontrado: " + request.modoPagoId())));
        }
        if (request.condicionPagoId() != null) {
            cliente.setCondicionPago(condicionPagoRepository.findById(request.condicionPagoId())
                    .orElseThrow(() -> new ResourceNotFoundException("Condición de pago no encontrada: " + request.condicionPagoId())));
        }

        cliente.setComercial(comercial);
        cliente.setActivo(true);
        cliente.setIdOdoo(null);
        cliente.setEstadoSync(EstadoSync.PENDENTE);
        cliente.setFechaModificacion(LocalDateTime.now());

        Cliente guardado = clienteRepository.save(cliente);
        intentarEnvioInmediato(guardado);
        return clienteMapper.toResponse(guardado);
    }

    /**
     * Intenta enviar el cliente recién guardado a Odoo en la misma transacción
     * del POST. Si Odoo responde, la entidad pasa a SINCRONIZADO con su
     * idOdoo y el commit lo persiste atomicamente con el alta. Esto permite
     * que un pedido enviado a continuación pueda resolver inmediatamente el
     * {@code partner_id} en Odoo, sin esperar al scheduler periódico.
     *
     * Si Odoo falla (caído, timeout, conflicto), capturamos la excepción
     * para NO tirar atrás el alta: el cliente queda en PENDENTE y el
     * scheduler lo reintentará. El POST sigue devolviendo 201 con el cliente.
     */
    private void intentarEnvioInmediato(Cliente cliente) {
        try {
            odooSyncService.enviarUno(cliente);
        } catch (Exception e) {
            log.warn("[POST /clientes] Cliente {} guardado pero envío inmediato a Odoo falló "
                    + "— queda PENDENTE para el scheduler: {}", cliente.getId(), e.getMessage());
        }
    }
}
