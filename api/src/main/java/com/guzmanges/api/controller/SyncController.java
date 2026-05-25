package com.guzmanges.api.controller;

import java.util.HashMap;
import java.util.Map;

import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.guzmanges.api.odoo.service.OdooMaestrosSyncService;
import com.guzmanges.api.odoo.service.OdooSyncService;
import com.guzmanges.api.odoo.service.SyncResult;

import lombok.RequiredArgsConstructor;

/**
 * Controlador para disparar la sincronización con Odoo de forma manual.
 * Restringido a administradores (ver SecurityConfig: /sync/** requiere rol ADMIN).
 */
@RestController
@RequestMapping("/sync")
@RequiredArgsConstructor
public class SyncController {

    private final OdooSyncService odooSyncService;
    private final OdooMaestrosSyncService odooMaestrosSyncService;

    /**
     * Sincroniza los clientes en ambos sentidos: importa desde Odoo y envía las altas pendientes.
     *
     * @return resumen con el número de importados y el resultado del envío
     */
    @PostMapping("/clientes")
    public Map<String, Object> sincronizarClientes() {
        int importados = odooSyncService.importarClientesDesdeOdoo();
        SyncResult enviados = odooSyncService.enviarClientesPendientes();

        Map<String, Object> resumen = new HashMap<>();
        resumen.put("importados", importados);
        resumen.put("enviados", enviados);
        return resumen;
    }

    /**
     * Sincroniza los datos maestros (modos y condiciones de pago) desde Odoo.
     *
     * @return mensaje de confirmación
     */
    @PostMapping("/maestros")
    public Map<String, String> sincronizarMaestros() {
        odooMaestrosSyncService.syncCondicionesPago();
        odooMaestrosSyncService.syncModosPago();
        return Map.of("estado", "Maestros sincronizados");
    }
}
