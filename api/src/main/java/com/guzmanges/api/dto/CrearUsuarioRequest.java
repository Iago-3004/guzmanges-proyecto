package com.guzmanges.api.dto;

import com.guzmanges.api.entity.TipoUsuario;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * Petición de alta de un usuario. Solo puede invocarla un ADMIN autenticado.
 *
 * El {@code nombreUsuario} y el {@code email} deben ser únicos en la BD;
 * si ya existen, el servicio devuelve HTTP 409.
 */
public record CrearUsuarioRequest(

        @NotBlank(message = "El nombre es obligatorio")
        @Size(max = 100, message = "El nombre no puede superar 100 caracteres")
        String nombre,

        @NotBlank(message = "El nombre de usuario es obligatorio")
        @Size(max = 50, message = "El nombre de usuario no puede superar 50 caracteres")
        String nombreUsuario,

        @NotBlank(message = "El email es obligatorio")
        @Email(message = "El email no tiene un formato válido")
        @Size(max = 150, message = "El email no puede superar 150 caracteres")
        String email,

        @NotBlank(message = "La contraseña es obligatoria")
        @Size(min = 4, max = 100, message = "La contraseña debe tener entre 4 y 100 caracteres")
        String contrasena,

        @NotNull(message = "El tipo de usuario es obligatorio")
        TipoUsuario tipoUsuario
) {
}
