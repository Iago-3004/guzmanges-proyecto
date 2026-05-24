package com.guzmanges.api.mapper;

import org.springframework.stereotype.Component;

import com.guzmanges.api.dto.ModoPagoResponse;
import com.guzmanges.api.entity.ModoPago;

/**
 * Conversión de la entidad ModoPago a su DTO de respuesta.
 */
@Component
public class ModoPagoMapper {

    public ModoPagoResponse toResponse(ModoPago modoPago) {
        return new ModoPagoResponse(
                modoPago.getId(),
                modoPago.getIdOdoo(),
                modoPago.getDescripcion(),
                modoPago.getActivo()
        );
    }
}
