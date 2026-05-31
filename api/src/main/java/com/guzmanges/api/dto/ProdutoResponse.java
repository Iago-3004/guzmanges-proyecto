package com.guzmanges.api.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * Datos de un producto tal y como los recibe la app.
 *
 * Refleja los campos públicos de la entidad {@link com.guzmanges.api.entity.Produto}.
 * Los productos son de solo lectura: se gestionan en Odoo y se importan al backend.
 */
public record ProdutoResponse(
        Long id,
        String idOdoo,
        String referencia,
        String codigoBarras,
        String descripcion,
        String tipoProduto,
        Integer stock,
        BigDecimal precioVenta,
        BigDecimal iva,
        String observaciones,
        LocalDateTime fechaModificacion
) {
}
