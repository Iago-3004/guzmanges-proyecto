package com.guzmanges.api.odoo.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import com.guzmanges.api.odoo.service.OdooMaestrosSyncService;
import com.guzmanges.api.odoo.service.OdooPedidosSyncService;
import com.guzmanges.api.odoo.service.OdooProductosSyncService;
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
    private final OdooProductosSyncService odooProductosSyncService;
    private final OdooPedidosSyncService odooPedidosSyncService;

    /**
     * Se ejecuta una vez al arrancar la aplicación (cuando el contexto está listo).
     * Realiza la sincronización inicial con Odoo en el orden de dependencias:
     * maestros → productos → clientes (en ambos sentidos) → pedidos pendientes.
     * Los pedidos van al final porque dependen de que sus clientes y productos
     * ya estén sincronizados con Odoo.
     */
    @EventListener(ApplicationReadyEvent.class)
    public void onApplicationReady() {
        log.info("======== SINCRONIZACIÓN INICIAL CON ODOO ========");
        sincronizarMaestros();
        sincronizarProductos();
        sincronizarClientes();
        enviarPedidosPendientes();
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
     * Sincronización periódica del catálogo de productos. Solo importación
     * (Odoo → BD local): los productos no se crean ni modifican desde la app.
     */
    @Scheduled(fixedDelayString = "${odoo.sync.productos.interval:3600000}",
               initialDelayString = "${odoo.sync.productos.interval:3600000}")
    public void syncProductosPeriodico() {
        log.info("[ODOO SYNC] Sincronización periódica de productos...");
        sincronizarProductos();
    }

    /**
     * Sincronización periódica de clientes en ambos sentidos: importa desde Odoo y
     * envía las altas pendientes. Tras los clientes se reintenta el envío de
     * pedidos pendientes: así, si un pedido quedó en espera porque su cliente
     * todavía no estaba en Odoo, en esta misma vuelta puede ya subirse.
     *
     * Antes de los clientes se refrescan los maestros (modos y condiciones de
     * pago): un cliente nuevo en Odoo puede referenciar un modo o condición que
     * todavía no esté en local; si no se cargase primero, el cliente quedaría
     * guardado con esa FK a null hasta que se modificase de nuevo en Odoo.
     */
    @Scheduled(fixedDelayString = "${odoo.sync.clientes.interval:900000}",
               initialDelayString = "${odoo.sync.clientes.interval:900000}")
    public void syncClientesPeriodico() {
        log.info("[ODOO SYNC] Sincronización periódica de clientes...");
        sincronizarMaestros();
        sincronizarClientes();
        enviarPedidosPendientes();
    }

    /**
     * Sincronización periódica del envío de pedidos a Odoo. Es el cierre del
     * ciclo bidireccional: convierte cada {@code BORRADOR + PENDENTE} local en
     * un {@code sale.order} de Odoo y reescribe los totales con los definitivos
     * que devuelve Odoo (aplicando la posición fiscal del cliente).
     */
    @Scheduled(fixedDelayString = "${odoo.sync.pedidos.interval:900000}",
               initialDelayString = "${odoo.sync.pedidos.interval:900000}")
    public void syncPedidosPeriodico() {
        log.info("[ODOO SYNC] Sincronización periódica de pedidos pendientes...");
        enviarPedidosPendientes();
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
     * Importa el catálogo de productos desde Odoo. Aísla los fallos para no detener
     * el resto de la sincronización.
     */
    private void sincronizarProductos() {
        try {
            int n = odooProductosSyncService.importarProductosDesdeOdoo();
            log.info("[ODOO -> DB] {} productos importados/actualizados desde Odoo", n);
        } catch (Exception e) {
            log.error("[ERROR] Fallo al importar productos desde Odoo: {}", e.getMessage());
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

    /**
     * Envía a Odoo los pedidos en BORRADOR + PENDENTE. Aísla el fallo para que
     * no detenga el resto de la sincronización.
     */
    private void enviarPedidosPendientes() {
        try {
            SyncResult envio = odooPedidosSyncService.enviarPedidosPendientes();
            if (envio.getTotal() > 0) {
                log.info("[DB -> ODOO] Envío de pedidos pendientes: {}", envio);
            }
        } catch (Exception e) {
            log.error("[ERROR] Fallo al enviar pedidos a Odoo: {}", e.getMessage());
        }
    }
}
