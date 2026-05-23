package com.guzmanges.api.security;

import java.nio.charset.StandardCharsets;
import java.util.Date;

import javax.crypto.SecretKey;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.stereotype.Component;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;

import lombok.extern.slf4j.Slf4j;

/**
 * Componente responsable de generar y validar los tokens JWT.
 *
 * Usa el algoritmo HMAC-SHA (HS256) con una clave secreta configurada en
 * {@code application.properties} ({@code guzmanges.jwt.secret}). El token
 * incluye el nombre de usuario como subject y el rol como claim adicional,
 * y caduca tras el tiempo definido en {@code guzmanges.jwt.expiration-ms}.
 *
 * Lo usa {@code AuthService} para emitir el token tras un login correcto, y
 * {@code JwtAuthenticationFilter} para validar el token en cada petición.
 */
@Component
@Slf4j
public class JwtTokenProvider {

    private final SecretKey key;
    private final long expirationMs;

    /**
     * Construye el proveedor a partir de la configuración de la aplicación.
     *
     * @param secret       cadena secreta para firmar los tokens (mínimo 256 bits para HS256)
     * @param expirationMs validez del token en milisegundos
     */
    public JwtTokenProvider(
            @Value("${guzmanges.jwt.secret}") String secret,
            @Value("${guzmanges.jwt.expiration-ms}") long expirationMs) {
        this.key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.expirationMs = expirationMs;
    }

    /**
     * Genera un token JWT firmado a partir de la autenticación del usuario.
     *
     * @param authentication autenticación validada por Spring Security
     * @return el token JWT en formato compacto (cadena Base64URL)
     */
    public String generateToken(Authentication authentication) {
        String username = authentication.getName();
        String role = authentication.getAuthorities().stream()
                .map(GrantedAuthority::getAuthority)
                .findFirst()
                .orElse("");

        Date ahora = new Date();
        Date expiracion = new Date(ahora.getTime() + expirationMs);

        return Jwts.builder()
                .subject(username)
                .claim("role", role)
                .issuedAt(ahora)
                .expiration(expiracion)
                .signWith(key)
                .compact();
    }

    /**
     * Extrae el nombre de usuario (subject) de un token.
     *
     * @param token token JWT
     * @return el nombre de usuario contenido en el token
     */
    public String getUsernameFromToken(String token) {
        return parseClaims(token).getSubject();
    }

    /**
     * Valida la firma y la expiración de un token.
     *
     * @param token token JWT a validar
     * @return {@code true} si el token es válido; {@code false} si está
     *         expirado, manipulado o malformado
     */
    public boolean validateToken(String token) {
        try {
            parseClaims(token);
            return true;
        } catch (JwtException | IllegalArgumentException e) {
            log.warn("Token JWT inválido: {}", e.getMessage());
            return false;
        }
    }

    /**
     * Devuelve la duración configurada del token en milisegundos.
     *
     * @return milisegundos de validez del token
     */
    public long getExpirationMs() {
        return expirationMs;
    }

    /**
     * Parsea y verifica un token, devolviendo sus claims.
     *
     * @param token token JWT
     * @return los claims del token
     * @throws JwtException si la firma no es válida o el token está expirado
     */
    private Claims parseClaims(String token) {
        return Jwts.parser()
                .verifyWith(key)
                .build()
                .parseSignedClaims(token)
                .getPayload();
    }
}
