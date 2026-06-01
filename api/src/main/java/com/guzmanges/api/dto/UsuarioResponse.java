package com.guzmanges.api.dto;

import com.guzmanges.api.entity.TipoUsuario;

/**
 * Datos de un usuario visibles desde la API. Nunca expone la contraseña
 * (ni siquiera el hash): el flujo de cambio de contraseña usa un endpoint
 * aparte y la contraseña actual no se devuelve nunca.
 */
public record UsuarioResponse(
        Long id,
        String nombre,
        String nombreUsuario,
        String email,
        TipoUsuario tipoUsuario
) {
}
