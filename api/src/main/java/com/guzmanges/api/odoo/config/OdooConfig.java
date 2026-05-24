package com.guzmanges.api.odoo.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

import lombok.Getter;
import lombok.Setter;

/**
 * Configuración de conexión con Odoo.
 *
 * Los parámetros se cargan desde application.properties (prefijo "odoo") que, a su vez,
 * los lee de variables de entorno: ODOO_URL, ODOO_DB, ODOO_USER, ODOO_APIKEY.
 */
@Configuration
@ConfigurationProperties(prefix = "odoo")
@Getter
@Setter
public class OdooConfig {

    /** URL base de la instancia de Odoo (ej: https://miempresa.odoo.com). */
    private String url;

    /** Nombre de la base de datos de Odoo. */
    private String database;

    /** Usuario (login) de Odoo. */
    private String username;

    /** Clave API del usuario de Odoo. */
    private String apikey;

    /**
     * Devuelve la URL del endpoint XML-RPC para autenticación.
     *
     * @return endpoint "common" de Odoo
     */
    public String getCommonEndpoint() {
        return url + "/xmlrpc/2/common";
    }

    /**
     * Devuelve la URL del endpoint XML-RPC para operaciones sobre modelos (CRUD).
     *
     * @return endpoint "object" de Odoo
     */
    public String getObjectEndpoint() {
        return url + "/xmlrpc/2/object";
    }
}
