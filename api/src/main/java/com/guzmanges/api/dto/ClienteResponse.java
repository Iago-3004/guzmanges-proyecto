package com.guzmanges.api.dto;

import com.guzmanges.api.entity.EstadoSync;

public record ClienteResponse(
        Long id,
        String idOdoo,
        String nombreComercial,
        String razonSocial,
        String cif,
        String direccion,
        String localidad,
        String codigoPostal,
        String provincia,
        String telefono,
        String movil,
        String email,
        String posicionFiscal,
        ModoPagoResponse modoPago,
        CondicionPagoResponse condicionPago,
        String comercial,
        Boolean activo,
        EstadoSync estadoSync
) {
}
