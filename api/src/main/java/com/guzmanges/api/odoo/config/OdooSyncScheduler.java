package com.guzmanges.api.odoo.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import com.guzmanges.api.odoo.service.OdooMaestrosSyncService;
import com.guzmanges.api.odoo.service.OdooSyncService;
import com.guzmanges.api.odoo.service.SyncResult;

import lombok.RequiredArgsConstructor;

/**
 * Gestiona la sincronización automática con Odoo.
 *
 * - Al arrancar la aplicación (ApplicationReadyEvent): ejecuta una sincronización inicial.
 * - Periódicamente (@Scheduled): vuelve a sincronizar los datos maestros.
 *
 * El intervalo se configura con la propiedad {@code odoo.sync.maestros.interval} (ms).
 * La sincronización puede desactivarse por completo con {@code odoo.sync.enabled=false}.
 * Cada paso captura sus excepciones: si Odoo no está accesible, la aplicación sigue funcionando.
 */
@Component
@ConditionalOnProperty(name = "odoo.sync.enabled", havingValue = "true", matchIfMissing = true)
@RequiredArgsConstructor
public class OdooSyncScheduler {

    private static final Logger log = LoggerFactory.getLogger(OdooSyncScheduler.class);

    private final OdooMaestrosSyncService odooMaestrosSyncService;
    private final OdooSyncService odooSyncService;

    /**
     * Se ejecuta una vez al arrancar la aplicación (cuando el contexto está listo).
     * Realiza la sincronización inicial con Odoo: primero los maestros y luego los clientes
     * (los clientes dependen de que los modos y condiciones de pago ya estén en local).
     */
    @EventListener(ApplicationReadyEvent.class)
    public void onApplicationReady() {
        log.info("======== SINCRONIZACIÓN INICIAL CON ODOO ========");
        sincronizarMaestros();
        sincronizarClientes();
        log.info("======== SINCRONIZACIÓN INICIAL FINALIZADA ========");
    }

    /**
     * Sincronización periódica de los datos maestros (modos y condiciones de pago).
     */
    @Scheduled(fixedDelayString = "${odoo.sync.maestros.interval:3600000}",
               initialDelayString = "${odoo.sync.maestros.interval:3600000}")
    public void syncMaestrosPeriodico() {
        log.info("[ODOO SYNC] Sincronización periódica de maestros (modos y condiciones de pago)...");
        sincronizarMaestros();
    }

    /**
     * Sincronización periódica de clientes en ambos sentidos: importa desde Odoo y
     * envía las altas pendientes.
     */
    @Scheduled(fixedDelayString = "${odoo.sync.clientes.interval:900000}",
               initialDelayString = "${odoo.sync.clientes.interval:900000}")
    public void syncClientesPeriodico() {
        log.info("[ODOO SYNC] Sincronización periódica de clientes...");
        sincronizarClientes();
    }

    /**
     * Lanza la sincronización de cada maestro de forma aislada, de modo que el fallo
     * de uno no impida sincronizar el resto.
     */
    private void sincronizarMaestros() {
        try {
            odooMaestrosSyncService.syncCondicionesPago();
        } catch (Exception e) {
            log.error("[ERROR] Fallo al sincronizar condiciones de pago: {}", e.getMessage());
        }
        try {
            odooMaestrosSyncService.syncModosPago();
        } catch (Exception e) {
            log.error("[ERROR] Fallo al sincronizar modos de pago: {}", e.getMessage());
        }
    }

    /**
     * Sincroniza los clientes en ambos sentidos (importar de Odoo + enviar los pendientes),
     * de forma aislada para que un fallo no detenga el resto.
     */
    private void sincronizarClientes() {
        try {
            int n = odooSyncService.importarClientesDesdeOdoo();
            log.info("[ODOO -> DB] {} clientes importados/actualizados desde Odoo", n);
        } catch (Exception e) {
            log.error("[ERROR] Fallo al importar clientes desde Odoo: {}", e.getMessage());
        }
        try {
            SyncResult envio = odooSyncService.enviarClientesPendientes();
            if (envio.getTotal() > 0) {
                log.info("[DB -> ODOO] Envío de clientes pendientes: {}", envio);
            }
        } catch (Exception e) {
            log.error("[ERROR] Fallo al enviar clientes a Odoo: {}", e.getMessage());
        }
    }
}
