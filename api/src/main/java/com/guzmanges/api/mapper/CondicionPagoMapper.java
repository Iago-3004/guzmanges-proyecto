package com.guzmanges.api.mapper;

import org.springframework.stereotype.Component;

import com.guzmanges.api.dto.CondicionPagoResponse;
import com.guzmanges.api.entity.CondicionPago;

/**
 * Conversión de la entidad CondicionPago a su DTO de respuesta.
 */
@Component
public class CondicionPagoMapper {

    public CondicionPagoResponse toResponse(CondicionPago condicionPago) {
        return new CondicionPagoResponse(
                condicionPago.getId(),
                condicionPago.getIdOdoo(),
                condicionPago.getDescripcion(),
                condicionPago.getActivo()
        );
    }
}
