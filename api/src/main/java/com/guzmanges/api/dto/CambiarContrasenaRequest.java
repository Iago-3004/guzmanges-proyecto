package com.guzmanges.api.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * Petición de cambio de contraseña de un usuario. Va por un endpoint propio
 * para no mezclarla con los datos generales del usuario y para permitir un
 * mensaje de error específico si no cumple la longitud mínima.
 */
public record CambiarContrasenaRequest(

        @NotBlank(message = "La contraseña es obligatoria")
        @Size(min = 4, max = 100, message = "La contraseña debe tener entre 4 y 100 caracteres")
        String contrasena
) {
}
