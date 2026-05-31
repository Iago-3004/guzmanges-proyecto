package com.guzmanges.api.dto;

import java.math.BigDecimal;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

/**
 * Línea de un pedido recibida desde la app.
 *
 * Solo {@link #productoId} y {@link #cantidade} son obligatorios. Si la app no
 * envía precio, IVA o recargo, el servicio los toma del producto y de la
 * posición fiscal del cliente. Si los envía, el servicio los respeta (útil
 * para precios negociados de última hora).
 */
public record CrearLineaRequest(

        @NotNull(message = "El producto es obligatorio")
        Long productoId,

        @NotNull(message = "La cantidad es obligatoria")
        @Positive(message = "La cantidad debe ser mayor que cero")
        Integer cantidade,

        @Min(value = 0, message = "El precio no puede ser negativo")
        BigDecimal precio,

        @Min(value = 0, message = "El IVA no puede ser negativo")
        BigDecimal iva,

        @Min(value = 0, message = "El recargo de equivalencia no puede ser negativo")
        BigDecimal recargoEquivalencia
) {
}
