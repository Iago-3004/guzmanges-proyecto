package com.guzmanges.api.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.guzmanges.api.dto.BloqueResultadoSync;
import com.guzmanges.api.dto.SyncBidireccionalResponse;
import com.guzmanges.api.dto.SyncCompletaResponse;
import com.guzmanges.api.dto.SyncMaestrosResponse;
import com.guzmanges.api.dto.SyncProductosResponse;
import com.guzmanges.api.odoo.service.OdooMaestrosSyncService;
import com.guzmanges.api.odoo.service.OdooPedidosSyncService;
import com.guzmanges.api.odoo.service.OdooProductosSyncService;
import com.guzmanges.api.odoo.service.OdooSyncService;
import com.guzmanges.api.odoo.service.SyncResult;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;

/**
 * Controlador para disparar la sincronización con Odoo de forma manual.
 * Restringido a administradores (ver SecurityConfig: /sync/** requiere rol ADMIN).
 *
 * Cada endpoint dispara el mismo servicio que ejecuta el scheduler periódico,
 * así que las reglas de negocio (filtros, reconciliación de borrados, etc.)
 * son idénticas. Pensado para que un ADMIN pueda forzar una sincronización
 * sin esperar al siguiente tic del scheduler.
 */
@RestController
@RequestMapping("/sync")
@RequiredArgsConstructor
@Tag(name = "Sincronización Odoo", description = "Disparo manual de la sincronización con Odoo (solo ADMIN).")
public class SyncController {

    private static final Logger log = LoggerFactory.getLogger(SyncController.class);

    private final OdooSyncService odooSyncService;
    private final OdooMaestrosSyncService odooMaestrosSyncService;
    private final OdooProductosSyncService odooProductosSyncService;
    private final OdooPedidosSyncService odooPedidosSyncService;

    /**
     * Sincroniza los datos maestros (modos y condiciones de pago) desde Odoo.
     * Lectura unidireccional: los catálogos se gestionan en Odoo.
     *
     * @return mensaje de confirmación
     */
    @Operation(summary = "Sincronizar maestros",
            description = "Importa modos y condiciones de pago desde Odoo (read-only).")
    @PostMapping("/maestros")
    public SyncMaestrosResponse sincronizarMaestros(Authentication authentication) {
        log.info("[SYNC MANUAL] '{}' inició sincronización de maestros",
                authentication.getName());
        odooMaestrosSyncService.syncCondicionesPago();
        odooMaestrosSyncService.syncModosPago();
        return new SyncMaestrosResponse("Maestros sincronizados");
    }

    /**
     * Sincroniza los productos desde Odoo. Lectura unidireccional: el catálogo
     * se gestiona en Odoo y la app solo lo cachea.
     *
     * @return resumen con el número de productos importados/actualizados
     */
    @Operation(summary = "Sincronizar productos",
            description = "Importa el catálogo de productos desde Odoo (read-only).")
    @PostMapping("/productos")
    public SyncProductosResponse sincronizarProductos(Authentication authentication) {
        log.info("[SYNC MANUAL] '{}' inició sincronización de productos",
                authentication.getName());
        int importados = odooProductosSyncService.importarProductosDesdeOdoo();
        return new SyncProductosResponse(importados);
    }

    /**
     * Sincroniza los clientes en ambos sentidos: importa desde Odoo y envía las altas pendientes.
     *
     * @return resumen con el número de importados y el resultado del envío
     */
    @Operation(summary = "Sincronizar clientes",
            description = "Bidireccional: importa de Odoo y envía las altas locales pendientes.")
    @PostMapping("/clientes")
    public SyncBidireccionalResponse sincronizarClientes(Authentication authentication) {
        log.info("[SYNC MANUAL] '{}' inició sincronización de clientes",
                authentication.getName());
        int importados = odooSyncService.importarClientesDesdeOdoo();
        SyncResult enviados = odooSyncService.enviarClientesPendientes();
        return new SyncBidireccionalResponse(importados, enviados);
    }

    /**
     * Sincroniza los pedidos en ambos sentidos: importa desde Odoo
     * (solo los confirmados y los cancelados, según la reconciliación) y envía
     * los pedidos locales pendientes que aún no se hayan subido.
     *
     * @return resumen con el número de importados y el resultado del envío
     */
    @Operation(summary = "Sincronizar pedidos",
            description = "Bidireccional: importa de Odoo y envía los pedidos locales pendientes.")
    @PostMapping("/pedidos")
    public SyncBidireccionalResponse sincronizarPedidos(Authentication authentication) {
        log.info("[SYNC MANUAL] '{}' inició sincronización de pedidos",
                authentication.getName());
        int importados = odooPedidosSyncService.importarPedidosDesdeOdoo();
        SyncResult enviados = odooPedidosSyncService.enviarPedidosPendientes();
        return new SyncBidireccionalResponse(importados, enviados);
    }

    /**
     * Ejecuta la sincronización completa con Odoo en el orden adecuado:
     * <ol>
     *   <li>Maestros (modos y condiciones de pago): los clientes los referencian.</li>
     *   <li>Productos: las líneas de pedido los referencian.</li>
     *   <li>Clientes (bidireccional): los pedidos los referencian, así que las
     *       altas locales tienen que subir antes que los pedidos.</li>
     *   <li>Pedidos (bidireccional).</li>
     * </ol>
     *
     * Cada bloque se ejecuta dentro de su propia transacción (en el service
     * correspondiente), así que un fallo en un paso no corrompe los demás:
     * capturamos la excepción, la registramos y devolvemos un detalle del
     * error en el resumen, pero seguimos con los siguientes bloques. El
     * cliente recibe siempre HTTP 200 con el desglose para que un ADMIN
     * pueda ver de un vistazo qué partes han ido bien y cuáles no.
     *
     * @return resumen estructurado con el resultado de cada bloque
     */
    @Operation(summary = "Sincronización completa",
            description = "Ejecuta maestros, productos, clientes y pedidos en el orden correcto. "
                    + "Captura errores por bloque para que un fallo no aborte el resto.")
    @PostMapping("/completa")
    public SyncCompletaResponse sincronizacionCompleta(Authentication authentication) {
        log.info("[SYNC MANUAL] '{}' inició sincronización completa",
                authentication.getName());
        BloqueResultadoSync maestros = ejecutarMaestros();
        BloqueResultadoSync productos = ejecutarProductos();
        BloqueResultadoSync clientes = ejecutarClientes();
        BloqueResultadoSync pedidos = ejecutarPedidos();
        return new SyncCompletaResponse(maestros, productos, clientes, pedidos);
    }

    private BloqueResultadoSync ejecutarMaestros() {
        try {
            odooMaestrosSyncService.syncCondicionesPago();
            odooMaestrosSyncService.syncModosPago();
            return BloqueResultadoSync.ok("OK");
        } catch (Exception e) {
            return registrarError("maestros", e);
        }
    }

    private BloqueResultadoSync ejecutarProductos() {
        try {
            return BloqueResultadoSync.importados(
                    odooProductosSyncService.importarProductosDesdeOdoo());
        } catch (Exception e) {
            return registrarError("productos", e);
        }
    }

    private BloqueResultadoSync ejecutarClientes() {
        try {
            int importados = odooSyncService.importarClientesDesdeOdoo();
            SyncResult enviados = odooSyncService.enviarClientesPendientes();
            return BloqueResultadoSync.bidireccional(importados, enviados);
        } catch (Exception e) {
            return registrarError("clientes", e);
        }
    }

    private BloqueResultadoSync ejecutarPedidos() {
        try {
            int importados = odooPedidosSyncService.importarPedidosDesdeOdoo();
            SyncResult enviados = odooPedidosSyncService.enviarPedidosPendientes();
            return BloqueResultadoSync.bidireccional(importados, enviados);
        } catch (Exception e) {
            return registrarError("pedidos", e);
        }
    }

    /**
     * Registra el fallo de un bloque en los logs y empaqueta el mensaje para
     * que el ADMIN lo vea en la respuesta. Centralizado para mantener el
     * mismo formato de log en los cuatro bloques.
     */
    private BloqueResultadoSync registrarError(String bloque, Exception e) {
        log.error("[SYNC COMPLETA] Paso '{}' falló: {}", bloque, e.getMessage(), e);
        String mensaje = e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName();
        return BloqueResultadoSync.error(mensaje);
    }
}
