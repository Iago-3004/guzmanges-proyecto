package com.guzmanges.api.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;

public record CrearClienteRequest(

        @NotBlank(message = "El nombre comercial es obligatorio")
        String nombreComercial,

        @NotBlank(message = "La razón social es obligatoria")
        String razonSocial,

        @NotBlank(message = "El CIF es obligatorio")
        String cif,

        String direccion,
        String localidad,
        String codigoPostal,
        String provincia,
        String telefono,
        String movil,

        @Email(message = "El email no tiene un formato válido")
        String email,

        Long modoPagoId,
        Long condicionPagoId
) {
}
