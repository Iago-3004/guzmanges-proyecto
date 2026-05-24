package com.guzmanges.api.dto;

public record ModoPagoResponse(
        Long id,
        String idOdoo,
        String descripcion,
        Boolean activo
) {
}
