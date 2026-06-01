package com.guzmanges.api.dto;

import com.guzmanges.api.odoo.service.SyncResult;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * Resultado de un bloque concreto dentro de la sincronización completa
 * (maestros, productos, clientes o pedidos). Como cada bloque tiene distinta
 * naturaleza, los campos son todos opcionales y se rellenan según corresponda:
 * <ul>
 *   <li>Bloque maestros: {@code estado} = "OK".</li>
 *   <li>Bloque productos: {@code importados} = N.</li>
 *   <li>Bloque clientes/pedidos: {@code importados} = N y {@code enviados} con el desglose.</li>
 *   <li>Si el bloque falla: {@code error} con el mensaje; el resto null.</li>
 * </ul>
 *
 * Los nulls se omiten globalmente a nivel de aplicación
 * ({@code spring.jackson.default-property-inclusion=non_null}), así que la
 * respuesta JSON solo contiene los campos aplicables a cada bloque.
 */
@Schema(description = "Resultado de un bloque de la sincronización completa. "
        + "Solo se incluyen los campos aplicables al bloque concreto.")
public record BloqueResultadoSync(
        @Schema(description = "Número de registros creados o actualizados en MySQL (bloques de productos, clientes, pedidos).",
                example = "15")
        Integer importados,
        @Schema(description = "Resultado del envío de los pendientes a Odoo (bloques bidireccionales: clientes, pedidos).")
        SyncResult enviados,
        @Schema(description = "Estado textual de bloques sin contadores (maestros).", example = "OK")
        String estado,
        @Schema(description = "Mensaje de error si el bloque falló; null si terminó correctamente.",
                example = "Connection refused: no further information")
        String error
) {

    public static BloqueResultadoSync ok(String estado) {
        return new BloqueResultadoSync(null, null, estado, null);
    }

    public static BloqueResultadoSync importados(int importados) {
        return new BloqueResultadoSync(importados, null, null, null);
    }

    public static BloqueResultadoSync bidireccional(int importados, SyncResult enviados) {
        return new BloqueResultadoSync(importados, enviados, null, null);
    }

    public static BloqueResultadoSync error(String mensaje) {
        return new BloqueResultadoSync(null, null, null, mensaje);
    }
}
