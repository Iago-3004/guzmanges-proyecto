package com.guzmanges.api.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * Respuesta de {@code POST /sync/maestros}. Los maestros (modos y condiciones
 * de pago) son de lectura unidireccional desde Odoo, así que basta con
 * indicar si la operación se completó correctamente; el detalle se registra
 * en los logs del servidor.
 */
@Schema(description = "Resultado de la sincronización de maestros (modos y condiciones de pago).")
public record SyncMaestrosResponse(
        @Schema(description = "Estado de la sincronización.", example = "Maestros sincronizados")
        String estado
) {
}
