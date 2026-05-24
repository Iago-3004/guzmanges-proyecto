package com.guzmanges.api.service;

import java.time.LocalDateTime;
import java.util.List;

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
import com.guzmanges.api.repository.ClienteRepository;
import com.guzmanges.api.repository.CondicionPagoRepository;
import com.guzmanges.api.repository.ModoPagoRepository;
import com.guzmanges.api.repository.UsuarioRepository;

import lombok.RequiredArgsConstructor;

/**
 * Lógica de negocio de los clientes: consulta de la cartera y alta de nuevos clientes.
 * Las altas quedan pendientes de envío a Odoo (estadoSync = PENDENTE).
 */
@Service
@RequiredArgsConstructor
public class ClienteService {

    private final ClienteRepository clienteRepository;
    private final ModoPagoRepository modoPagoRepository;
    private final CondicionPagoRepository condicionPagoRepository;
    private final UsuarioRepository usuarioRepository;
    private final ClienteMapper clienteMapper;

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
        return clienteMapper.toResponse(guardado);
    }
}
