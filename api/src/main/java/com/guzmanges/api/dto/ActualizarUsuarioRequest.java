package com.guzmanges.api.dto;

import com.guzmanges.api.entity.TipoUsuario;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * Petición de edición de un usuario existente.
 *
 * Deliberadamente NO incluye {@code nombreUsuario} (no se permite renombrar
 * para no romper la pista de auditoría implícita ni los inicios de sesión
 * en curso) ni {@code contrasena} (se cambia por su endpoint específico).
 */
public record ActualizarUsuarioRequest(

        @NotBlank(message = "El nombre es obligatorio")
        @Size(max = 100, message = "El nombre no puede superar 100 caracteres")
        String nombre,

        @NotBlank(message = "El email es obligatorio")
        @Email(message = "El email no tiene un formato válido")
        @Size(max = 150, message = "El email no puede superar 150 caracteres")
        String email,

        @NotNull(message = "El tipo de usuario es obligatorio")
        TipoUsuario tipoUsuario
) {
}
