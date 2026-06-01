package com.guzmanges.api.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * Respuesta de {@code POST /sync/completa}. Agrupa el resultado de cada uno
 * de los cuatro bloques que componen una sincronización completa con Odoo,
 * en el orden en el que se ejecutan (que es el orden lógico de dependencias).
 */
@Schema(description = "Resultado consolidado de la sincronización completa con Odoo.")
public record SyncCompletaResponse(
        @Schema(description = "Bloque 1: modos y condiciones de pago.")
        BloqueResultadoSync maestros,
        @Schema(description = "Bloque 2: catálogo de productos.")
        BloqueResultadoSync productos,
        @Schema(description = "Bloque 3: clientes (bidireccional).")
        BloqueResultadoSync clientes,
        @Schema(description = "Bloque 4: pedidos (bidireccional).")
        BloqueResultadoSync pedidos
) {
}
