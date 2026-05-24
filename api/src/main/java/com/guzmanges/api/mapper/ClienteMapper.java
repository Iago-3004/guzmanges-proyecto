package com.guzmanges.api.mapper;

import org.springframework.stereotype.Component;

import com.guzmanges.api.dto.ClienteResponse;
import com.guzmanges.api.entity.Cliente;

import lombok.RequiredArgsConstructor;

/**
 * Conversión de la entidad Cliente a su DTO de respuesta.
 * Reutiliza los mappers de los catálogos para anidar el modo y la condición de pago.
 */
@Component
@RequiredArgsConstructor
public class ClienteMapper {

    private final ModoPagoMapper modoPagoMapper;
    private final CondicionPagoMapper condicionPagoMapper;

    public ClienteResponse toResponse(Cliente cliente) {
        return new ClienteResponse(
                cliente.getId(),
                cliente.getIdOdoo(),
                cliente.getNombreComercial(),
                cliente.getRazonSocial(),
                cliente.getCif(),
                cliente.getDireccion(),
                cliente.getLocalidad(),
                cliente.getCodigoPostal(),
                cliente.getProvincia(),
                cliente.getTelefono(),
                cliente.getMovil(),
                cliente.getEmail(),
                cliente.getPosicionFiscal(),
                cliente.getModoPago() != null ? modoPagoMapper.toResponse(cliente.getModoPago()) : null,
                cliente.getCondicionPago() != null ? condicionPagoMapper.toResponse(cliente.getCondicionPago()) : null,
                cliente.getComercial() != null ? cliente.getComercial().getNombreUsuario() : null,
                cliente.getActivo(),
                cliente.getEstadoSync()
        );
    }
}
