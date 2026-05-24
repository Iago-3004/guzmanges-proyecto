package com.guzmanges.api.config;

import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.authentication.configuration.AuthenticationConfiguration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.HttpStatusEntryPoint;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.http.HttpStatus;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import com.guzmanges.api.security.JwtAuthenticationFilter;

import lombok.RequiredArgsConstructor;

/**
 * Configuración de Spring Security para una API REST stateless protegida con JWT.
 *
 * Puntos clave:
 * <ul>
 *   <li>Sin estado de sesión ({@code STATELESS}): cada petición se autentica por
 *       su token JWT, no hay sesión HTTP.</li>
 *   <li>CSRF desactivado: no aplica en una API REST sin cookies de sesión.</li>
 *   <li>Endpoints públicos: todo lo que cuelga de {@code /auth/**} (login).
 *       El resto requiere autenticación.</li>
 *   <li>El {@link JwtAuthenticationFilter} se ejecuta antes del filtro estándar
 *       de usuario/contraseña para autenticar a partir del token.</li>
 *   <li>CORS configurable desde {@code application.properties}
 *       ({@code guzmanges.cors.allowed-origins}), por defecto {@code http://localhost:*}
 *       para permitir el desarrollo del frontend Flutter.</li>
 * </ul>
 */
@Configuration
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtAuthenticationFilter;

    /**
     * Codificador de contraseñas basado en BCrypt. Se usa tanto para cifrar
     * las contraseñas al crear usuarios como para verificarlas en el login.
     *
     * @return el codificador BCrypt
     */
    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    /**
     * Expone el {@link AuthenticationManager} de Spring Security como bean para
     * que el {@code AuthService} pueda usarlo al autenticar el login.
     *
     * @param config configuración de autenticación proporcionada por Spring
     * @return el gestor de autenticación
     * @throws Exception si no se puede obtener el gestor de autenticación
     */
    @Bean
    public AuthenticationManager authenticationManager(AuthenticationConfiguration config) throws Exception {
        return config.getAuthenticationManager();
    }

    /**
     * Define la cadena de filtros de seguridad: CORS, sin CSRF, sesiones sin
     * estado, respuesta 401 ante peticiones no autenticadas, rutas públicas
     * ({@code /auth/**}) frente a protegidas, e inserción del filtro JWT antes
     * del filtro de usuario/contraseña.
     *
     * @param http configurador de seguridad HTTP
     * @return la cadena de filtros construida
     * @throws Exception si falla la configuración
     */
    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
                .cors(Customizer.withDefaults())
                .csrf(AbstractHttpConfigurer::disable)
                .sessionManagement(session -> session
                        .sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .exceptionHandling(ex -> ex
                        .authenticationEntryPoint(new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED)))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/auth/**").permitAll()
                        .anyRequest().authenticated())
                .addFilterBefore(jwtAuthenticationFilter,
                        UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }

    /**
     * Configura la política CORS a partir de los orígenes permitidos definidos
     * en {@code application.properties}. Spring Security la aplica al activar
     * {@code .cors(Customizer.withDefaults())} en la cadena de filtros.
     *
     * @param allowedOrigins lista de orígenes permitidos (admite patrones con comodín)
     * @return la fuente de configuración CORS para todas las rutas
     */
    @Bean
    public CorsConfigurationSource corsConfigurationSource(
            @Value("${guzmanges.cors.allowed-origins}") List<String> allowedOrigins) {
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOriginPatterns(allowedOrigins);
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"));
        config.setAllowedHeaders(List.of("*"));
        config.setAllowCredentials(true);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }
}
