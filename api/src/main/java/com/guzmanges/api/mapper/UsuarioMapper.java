package com.guzmanges.api.mapper;

import org.springframework.stereotype.Component;

import com.guzmanges.api.dto.UsuarioResponse;
import com.guzmanges.api.entity.Usuario;

/**
 * Convierte entidades {@link Usuario} a su DTO de respuesta. Como pieza
 * separada para no acoplar el service con la forma del JSON expuesto.
 */
@Component
public class UsuarioMapper {

    /**
     * Construye un {@link UsuarioResponse} a partir de la entidad. Omite
     * deliberadamente la contraseña (el hash BCrypt no se devuelve nunca,
     * ni siquiera al propio usuario).
     *
     * @param usuario entidad de usuario
     * @return DTO sin contraseña
     */
    public UsuarioResponse toResponse(Usuario usuario) {
        return new UsuarioResponse(
                usuario.getId(),
                usuario.getNombre(),
                usuario.getNombreUsuario(),
                usuario.getEmail(),
                usuario.getTipoUsuario()
        );
    }
}
