package com.guzmanges.api.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Service;

import com.guzmanges.api.dto.JwtResponse;
import com.guzmanges.api.dto.LoginRequest;
import com.guzmanges.api.entity.Usuario;
import com.guzmanges.api.repository.UsuarioRepository;
import com.guzmanges.api.security.JwtTokenProvider;

import lombok.RequiredArgsConstructor;

/**
 * Servicio de autenticación de usuarios.
 *
 * Coordina el proceso de login: delega la validación de credenciales en el
 * {@link AuthenticationManager} de Spring Security, genera el token JWT con el
 * {@link JwtTokenProvider} y construye la respuesta con los datos del usuario.
 */
@Service
@RequiredArgsConstructor
public class AuthService {

    private static final Logger log = LoggerFactory.getLogger(AuthService.class);

    private final AuthenticationManager authenticationManager;
    private final JwtTokenProvider jwtTokenProvider;
    private final UsuarioRepository usuarioRepository;

    /**
     * Autentica al usuario con sus credenciales y, si son válidas, genera un
     * token JWT junto con los datos básicos de la sesión.
     *
     * @param request credenciales de acceso (nombre de usuario y contraseña)
     * @return la respuesta con el token, el nombre de usuario, el rol y la
     *         duración del token en milisegundos
     * @throws org.springframework.security.authentication.BadCredentialsException
     *         si las credenciales no son válidas
     */
    public JwtResponse login(LoginRequest request) {
        Authentication authentication;
        try {
            authentication = authenticationManager.authenticate(
                    new UsernamePasswordAuthenticationToken(
                            request.nombreUsuario(), request.contrasena()));
        } catch (BadCredentialsException e) {
            // El username se loguea para poder detectar intentos de
            // brute-force. La contraseña NUNCA se loguea.
            log.warn("[AUTH] Intento fallido para usuario '{}': credenciales incorrectas",
                    request.nombreUsuario());
            throw e;
        }

        String token = jwtTokenProvider.generateToken(authentication);

        Usuario usuario = usuarioRepository.findByNombreUsuario(request.nombreUsuario())
                .orElseThrow();

        log.info("[AUTH] Usuario '{}' inició sesión correctamente (rol: {})",
                usuario.getNombreUsuario(), usuario.getTipoUsuario());

        return new JwtResponse(
                token,
                usuario.getNombreUsuario(),
                usuario.getTipoUsuario(),
                jwtTokenProvider.getExpirationMs());
    }
}
