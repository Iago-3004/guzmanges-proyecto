package com.guzmanges.api.dto;

import java.math.BigDecimal;

/**
 * Línea de un pedido tal como se devuelve a la app.
 *
 * Los campos descriptivos del producto ({@code codigoProducto}, {@code descripcion})
 * se guardan denormalizados en la línea para que el detalle del pedido pueda
 * pintarse aunque el producto haya cambiado de nombre o se haya borrado en Odoo.
 */
public record LineaResponse(
        Long id,
        Long productoId,
        String codigoProducto,
        String descripcion,
        BigDecimal precio,
        BigDecimal iva,
        BigDecimal recargoEquivalencia,
        Integer cantidade,
        BigDecimal subtotal
) {
}
