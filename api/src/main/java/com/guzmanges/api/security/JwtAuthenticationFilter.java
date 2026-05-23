package com.guzmanges.api.security;

import java.io.IOException;

import org.springframework.lang.NonNull;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import lombok.RequiredArgsConstructor;

/**
 * Filtro que se ejecuta una vez por petición y autentica al usuario a partir
 * del token JWT presente en la cabecera {@code Authorization}.
 *
 * Flujo en cada petición:
 * <ol>
 *   <li>Extrae el token de la cabecera {@code Authorization: Bearer <token>}.</li>
 *   <li>Si el token es válido, carga el usuario y establece la autenticación
 *       en el {@link SecurityContextHolder}.</li>
 *   <li>Si no hay token o no es válido, deja pasar la petición sin autenticar;
 *       será Spring Security quien rechace el acceso a los endpoints protegidos
 *       (HTTP 401).</li>
 * </ol>
 *
 * Se registra antes del {@code UsernamePasswordAuthenticationFilter} en la
 * cadena de seguridad (ver {@code SecurityConfig}).
 */
@Component
@RequiredArgsConstructor
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private static final String HEADER = "Authorization";
    private static final String PREFIX = "Bearer ";

    private final JwtTokenProvider jwtTokenProvider;
    private final CustomUserDetailsService userDetailsService;

    /**
     * Procesa cada petición HTTP: si encuentra un token JWT válido en la
     * cabecera, autentica al usuario en el contexto de seguridad. En cualquier
     * caso, deja continuar la cadena de filtros.
     *
     * @param request     petición HTTP entrante
     * @param response    respuesta HTTP
     * @param filterChain cadena de filtros a la que se delega tras procesar
     * @throws ServletException si falla el procesamiento del servlet
     * @throws IOException      si ocurre un error de entrada/salida
     */
    @Override
    protected void doFilterInternal(
            @NonNull HttpServletRequest request,
            @NonNull HttpServletResponse response,
            @NonNull FilterChain filterChain) throws ServletException, IOException {

        String token = extractToken(request);

        if (token != null && jwtTokenProvider.validateToken(token)) {
            String username = jwtTokenProvider.getUsernameFromToken(token);
            UserDetails userDetails = userDetailsService.loadUserByUsername(username);

            UsernamePasswordAuthenticationToken authentication =
                    new UsernamePasswordAuthenticationToken(
                            userDetails, null, userDetails.getAuthorities());
            authentication.setDetails(
                    new WebAuthenticationDetailsSource().buildDetails(request));

            SecurityContextHolder.getContext().setAuthentication(authentication);
        }

        filterChain.doFilter(request, response);
    }

    /**
     * Extrae el token JWT de la cabecera {@code Authorization}.
     *
     * @param request petición HTTP entrante
     * @return el token sin el prefijo "Bearer ", o {@code null} si no está presente
     */
    private String extractToken(HttpServletRequest request) {
        String header = request.getHeader(HEADER);
        if (header != null && header.startsWith(PREFIX)) {
            return header.substring(PREFIX.length());
        }
        return null;
    }
}
