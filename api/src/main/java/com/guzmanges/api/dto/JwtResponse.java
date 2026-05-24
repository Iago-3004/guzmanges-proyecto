package com.guzmanges.api.dto;

import com.guzmanges.api.entity.TipoUsuario;

public record JwtResponse(
        String token,
        String nombreUsuario,
        TipoUsuario rol,
        long expiraEn
) {
}
