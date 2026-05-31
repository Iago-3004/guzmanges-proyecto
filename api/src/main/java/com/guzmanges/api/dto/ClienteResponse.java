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
        /*
         * Indica si el cliente está sujeto al régimen de recargo de equivalencia.
         * Lo calcula el ClienteMapper a partir del nombre de la posición fiscal,
         * para que la app no tenga que interpretar la cadena: pregunta el flag y
         * aplica las tablas de RE (5.2 % / 1.4 % / 0.5 %) sólo si es true.
         */
        Boolean recargoEquivalencia,
        ModoPagoResponse modoPago,
        CondicionPagoResponse condicionPago,
        String comercial,
        Boolean activo,
        EstadoSync estadoSync
) {
}
