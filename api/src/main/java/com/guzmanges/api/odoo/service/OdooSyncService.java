package com.guzmanges.api.odoo.service;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.guzmanges.api.entity.Cliente;
import com.guzmanges.api.entity.CondicionPago;
import com.guzmanges.api.entity.EstadoSync;
import com.guzmanges.api.entity.ModoPago;
import com.guzmanges.api.odoo.mapper.OdooClienteMapper;
import com.guzmanges.api.odoo.repository.OdooClienteRepository;
import com.guzmanges.api.repository.ClienteRepository;
import com.guzmanges.api.repository.CondicionPagoRepository;
import com.guzmanges.api.repository.ModoPagoRepository;

import lombok.RequiredArgsConstructor;

/**
 * Servicio de sincronización de clientes con Odoo.
 *
 * En este paso implementa la importación (Odoo → MySQL): refleja en la BD local los clientes
 * existentes en Odoo. El envío de las altas locales (MySQL → Odoo) se añade en el paso siguiente.
 */
@Service
@RequiredArgsConstructor
public class OdooSyncService {

    private static final Logger log = LoggerFactory.getLogger(OdooSyncService.class);

    private final ClienteRepository clienteRepository;
    private final CondicionPagoRepository condicionPagoRepository;
    private final ModoPagoRepository modoPagoRepository;
    private final OdooClienteRepository odooClienteRepository;
    private final OdooClienteMapper odooClienteMapper;

    /**
     * Importa los clientes de Odoo a la BD local.
     * Para cada cliente de Odoo: si ya existe en local (por idOdoo) actualiza sus datos,
     * y si no existe lo crea. Los clientes locales sin idOdoo (altas pendientes de enviar)
     * no se ven afectados.
     *
     * @return número de clientes importados o actualizados
     */
    @Transactional
    public int importarClientesDesdeOdoo() {
        log.info("=== IMPORTANDO CLIENTES DESDE ODOO ===");
        List<Map<String, Object>> clientesOdoo = odooClienteRepository.findClientes();
        log.info("Clientes encontrados en Odoo: {}", clientesOdoo.size());

        int nuevos = 0;
        int actualizados = 0;
        for (Map<String, Object> datosOdoo : clientesOdoo) {
            try {
                String idOdoo = String.valueOf(((Number) datosOdoo.get("id")).longValue());
                Cliente desdeOdoo = odooClienteMapper.fromOdooToCliente(
                        datosOdoo, this::buscarCondicionPago, this::buscarModoPago);

                Optional<Cliente> existente = clienteRepository.findByIdOdoo(idOdoo);
                if (existente.isPresent()) {
                    Cliente cliente = existente.get();
                    copiarDatosDeOdoo(cliente, desdeOdoo);
                    clienteRepository.save(cliente);
                    actualizados++;
                } else {
                    clienteRepository.save(desdeOdoo);
                    nuevos++;
                    log.info("[ODOO -> DB] Nuevo cliente: {} (idOdoo: {})", desdeOdoo.getRazonSocial(), idOdoo);
                }
            } catch (Exception e) {
                log.error("[ODOO -> DB] Error importando cliente idOdoo={}: {}", datosOdoo.get("id"), e.getMessage());
            }
        }

        log.info("=== CLIENTES: {} nuevos, {} actualizados (de {} en Odoo) ===",
                nuevos, actualizados, clientesOdoo.size());
        return nuevos + actualizados;
    }

    private CondicionPago buscarCondicionPago(String idOdoo) {
        return condicionPagoRepository.findByIdOdoo(idOdoo).orElse(null);
    }

    private ModoPago buscarModoPago(String idOdoo) {
        return modoPagoRepository.findByIdOdoo(idOdoo).orElse(null);
    }

    /**
     * Copia en el cliente local los datos provenientes de Odoo. No toca el comercial
     * (asignación local) ni el idOdoo (que ya está establecido).
     */
    private void copiarDatosDeOdoo(Cliente destino, Cliente desdeOdoo) {
        destino.setRazonSocial(desdeOdoo.getRazonSocial());
        destino.setCif(desdeOdoo.getCif());
        destino.setNombreComercial(desdeOdoo.getNombreComercial());
        destino.setDireccion(desdeOdoo.getDireccion());
        destino.setLocalidad(desdeOdoo.getLocalidad());
        destino.setCodigoPostal(desdeOdoo.getCodigoPostal());
        destino.setProvincia(desdeOdoo.getProvincia());
        destino.setTelefono(desdeOdoo.getTelefono());
        destino.setMovil(desdeOdoo.getMovil());
        destino.setEmail(desdeOdoo.getEmail());
        destino.setPosicionFiscal(desdeOdoo.getPosicionFiscal());
        destino.setCondicionPago(desdeOdoo.getCondicionPago());
        destino.setModoPago(desdeOdoo.getModoPago());
        destino.setActivo(desdeOdoo.getActivo());
        destino.setEstadoSync(EstadoSync.SINCRONIZADO);
        destino.setFechaModificacion(LocalDateTime.now());
    }
}
