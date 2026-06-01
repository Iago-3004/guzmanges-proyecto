package com.guzmanges.api.dto;

import com.guzmanges.api.odoo.service.SyncResult;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * Respuesta de las sincronizaciones bidireccionales ({@code POST /sync/clientes}
 * y {@code POST /sync/pedidos}). Incluye el recuento de registros importados
 * desde Odoo y el resultado del envío de los registros locales pendientes a
 * Odoo (con desglose de éxitos y errores).
 */
@Schema(description = "Resultado de una sincronización bidireccional con Odoo (importación + envío de pendientes).")
public record SyncBidireccionalResponse(
        @Schema(description = "Número de registros creados o actualizados en MySQL desde Odoo.", example = "15")
        int importados,
        @Schema(description = "Resultado del envío de los registros locales pendientes a Odoo.")
        SyncResult enviados
) {
}
