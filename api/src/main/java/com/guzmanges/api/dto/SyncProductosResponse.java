package com.guzmanges.api.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * Respuesta de {@code POST /sync/productos}. Los productos son de lectura
 * unidireccional desde Odoo, así que solo informamos del recuento de altas
 * y actualizaciones aplicadas en MySQL durante esta llamada.
 */
@Schema(description = "Resultado de la sincronización de productos (Odoo → MySQL).")
public record SyncProductosResponse(
        @Schema(description = "Número de productos creados o actualizados en MySQL.", example = "42")
        int importados
) {
}
