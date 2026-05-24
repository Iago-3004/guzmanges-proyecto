package com.guzmanges.api.dto;

public record CondicionPagoResponse(
        Long id,
        String idOdoo,
        String descripcion,
        Boolean activo
) {
}
