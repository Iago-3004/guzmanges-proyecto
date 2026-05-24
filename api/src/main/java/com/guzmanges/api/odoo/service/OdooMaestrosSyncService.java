package com.guzmanges.api.odoo.service;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.guzmanges.api.entity.CondicionPago;
import com.guzmanges.api.entity.ModoPago;
import com.guzmanges.api.odoo.repository.OdooCondicionPagoRepository;
import com.guzmanges.api.odoo.repository.OdooModoPagoRepository;
import com.guzmanges.api.odoo.util.OdooValueUtil;
import com.guzmanges.api.repository.CondicionPagoRepository;
import com.guzmanges.api.repository.ModoPagoRepository;

import lombok.RequiredArgsConstructor;

/**
 * Servicio de sincronización de los datos maestros con Odoo.
 *
 * Odoo es la fuente de verdad: estos catálogos solo se importan (Odoo → MySQL).
 * Para cada registro de Odoo se busca el equivalente local por su idOdoo; si existe
 * se actualiza cuando hay cambios, y si no existe se crea.
 */
@Service
@RequiredArgsConstructor
public class OdooMaestrosSyncService {

    private static final Logger log = LoggerFactory.getLogger(OdooMaestrosSyncService.class);

    private final CondicionPagoRepository condicionPagoRepository;
    private final ModoPagoRepository modoPagoRepository;
    private final OdooCondicionPagoRepository odooCondicionPagoRepository;
    private final OdooModoPagoRepository odooModoPagoRepository;

    /**
     * Sincroniza las condiciones de pago desde Odoo (account.payment.term) a la BD local.
     */
    @Transactional
    public void syncCondicionesPago() {
        log.info("=== SINCRONIZANDO CONDICIONES DE PAGO DESDE ODOO ===");
        List<Map<String, Object>> condicionesOdoo = odooCondicionPagoRepository.findAll();
        if (condicionesOdoo.isEmpty()) {
            log.warn("No se encontraron condiciones de pago en Odoo");
            return;
        }

        int nuevas = 0;
        int actualizadas = 0;
        for (Map<String, Object> cpOdoo : condicionesOdoo) {
            String idOdoo = String.valueOf(((Number) cpOdoo.get("id")).longValue());
            String nombre = OdooValueUtil.getStringValue(cpOdoo, "name");
            boolean activo = cpOdoo.get("active") instanceof Boolean b ? b : true;

            Optional<CondicionPago> existente = condicionPagoRepository.findByIdOdoo(idOdoo);
            if (existente.isPresent()) {
                CondicionPago cp = existente.get();
                boolean cambio = false;
                if (!Objects.equals(cp.getDescripcion(), nombre)) {
                    cp.setDescripcion(nombre);
                    cambio = true;
                }
                if (!Objects.equals(cp.getActivo(), activo)) {
                    cp.setActivo(activo);
                    cambio = true;
                }
                if (cambio) {
                    cp.setFechaModificacion(LocalDateTime.now());
                    condicionPagoRepository.save(cp);
                    actualizadas++;
                    log.info("[COND.PAGO] Actualizada: {} (idOdoo: {}, activo: {})", nombre, idOdoo, activo);
                }
            } else {
                CondicionPago cp = CondicionPago.builder()
                        .idOdoo(idOdoo)
                        .descripcion(nombre)
                        .activo(activo)
                        .fechaModificacion(LocalDateTime.now())
                        .build();
                condicionPagoRepository.save(cp);
                nuevas++;
                log.info("[COND.PAGO] Nueva: {} (idOdoo: {}, activo: {})", nombre, idOdoo, activo);
            }
        }
        log.info("=== CONDICIONES DE PAGO: {} nuevas, {} actualizadas (de {} en Odoo) ===",
                nuevas, actualizadas, condicionesOdoo.size());
    }

    /**
     * Sincroniza los modos de pago desde Odoo (account.payment.mode) a la BD local.
     */
    @Transactional
    public void syncModosPago() {
        log.info("=== SINCRONIZANDO MODOS DE PAGO DESDE ODOO ===");
        List<Map<String, Object>> modosOdoo = odooModoPagoRepository.findAll();
        if (modosOdoo.isEmpty()) {
            log.warn("No se encontraron modos de pago en Odoo");
            return;
        }

        int nuevos = 0;
        int actualizados = 0;
        for (Map<String, Object> mpOdoo : modosOdoo) {
            String idOdoo = String.valueOf(((Number) mpOdoo.get("id")).longValue());
            String nombre = OdooValueUtil.getStringValue(mpOdoo, "name");
            boolean activo = mpOdoo.get("active") instanceof Boolean b ? b : true;

            Optional<ModoPago> existente = modoPagoRepository.findByIdOdoo(idOdoo);
            if (existente.isPresent()) {
                ModoPago mp = existente.get();
                boolean cambio = false;
                if (!Objects.equals(mp.getDescripcion(), nombre)) {
                    mp.setDescripcion(nombre);
                    cambio = true;
                }
                if (!Objects.equals(mp.getActivo(), activo)) {
                    mp.setActivo(activo);
                    cambio = true;
                }
                if (cambio) {
                    mp.setFechaModificacion(LocalDateTime.now());
                    modoPagoRepository.save(mp);
                    actualizados++;
                    log.info("[MODO.PAGO] Actualizado: {} (idOdoo: {}, activo: {})", nombre, idOdoo, activo);
                }
            } else {
                ModoPago mp = ModoPago.builder()
                        .idOdoo(idOdoo)
                        .descripcion(nombre)
                        .activo(activo)
                        .fechaModificacion(LocalDateTime.now())
                        .build();
                modoPagoRepository.save(mp);
                nuevos++;
                log.info("[MODO.PAGO] Nuevo: {} (idOdoo: {}, activo: {})", nombre, idOdoo, activo);
            }
        }
        log.info("=== MODOS DE PAGO: {} nuevos, {} actualizados (de {} en Odoo) ===",
                nuevos, actualizados, modosOdoo.size());
    }
}
