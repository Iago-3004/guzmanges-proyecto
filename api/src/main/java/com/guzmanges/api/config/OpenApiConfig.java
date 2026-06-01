package com.guzmanges.api.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;

/**
 * Configuración de la documentación OpenAPI 3 y de Swagger UI.
 *
 * Springdoc detecta automáticamente los controladores REST y sus DTOs y genera
 * la especificación en {@code /v3/api-docs}; Swagger UI la consume y la renderiza
 * en {@code /swagger-ui.html}.
 *
 * Este bean añade dos cosas que no se deducen del código:
 * <ul>
 *   <li>La información de cabecera (título, versión, descripción, contacto y
 *       licencia) que aparece arriba en Swagger UI.</li>
 *   <li>Un esquema de seguridad de tipo "Bearer JWT" — con el nombre lógico
 *       {@code bearerAuth} — para que el botón "Authorize" de Swagger UI permita
 *       pegar un token y probar los endpoints protegidos. Sin esto, habría que
 *       añadir la cabecera {@code Authorization} a mano en cada petición.</li>
 * </ul>
 *
 * El requisito de seguridad se declara a nivel global ({@code addSecurityItem}):
 * cualquier endpoint hereda la necesidad de un JWT salvo que la cadena de
 * filtros de Spring Security lo abra explícitamente (p. ej. {@code /auth/**}).
 */
@Configuration
public class OpenApiConfig {

    /** Nombre lógico del esquema de seguridad referenciado desde el SecurityRequirement. */
    private static final String JWT_SCHEME = "bearerAuth";

    /**
     * Construye el documento OpenAPI con la información de cabecera y el esquema
     * de seguridad JWT.
     *
     * @return el {@link OpenAPI} que Springdoc completará con los controllers
     */
    @Bean
    public OpenAPI guzmangesOpenAPI() {
        return new OpenAPI()
                .info(new Info()
                        .title("GuzmanGes API")
                        .version("1.0.0")
                        .description("API REST de la aplicación de preventa B2B GuzmanGes. "
                                + "Cubre la gestión de clientes, productos y pedidos, "
                                + "y la sincronización bidireccional con Odoo. Todos los "
                                + "endpoints (excepto `/auth/**` y la propia documentación) "
                                + "requieren un JWT obtenido en `/auth/login`.")
                        .license(new License()
                                .name("Uso académico — Proyecto Final DAM")))
                .addSecurityItem(new SecurityRequirement().addList(JWT_SCHEME))
                .components(new Components()
                        .addSecuritySchemes(JWT_SCHEME, new SecurityScheme()
                                .type(SecurityScheme.Type.HTTP)
                                .scheme("bearer")
                                .bearerFormat("JWT")
                                .description("JWT obtenido en `POST /auth/login`. "
                                        + "Pulsa el botón 'Authorize' y pega solo el token "
                                        + "(sin el prefijo 'Bearer ').")));
    }
}
