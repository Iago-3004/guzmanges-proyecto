package com.guzmanges.api.odoo.client;

import com.guzmanges.api.odoo.config.OdooConfig;
import com.guzmanges.api.odoo.exception.OdooConnectionException;
import com.guzmanges.api.odoo.exception.OdooOperationException;
import org.apache.xmlrpc.XmlRpcException;
import org.apache.xmlrpc.client.XmlRpcClient;
import org.apache.xmlrpc.client.XmlRpcClientConfigImpl;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.net.MalformedURLException;
import java.net.URL;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Cliente XML-RPC genérico para comunicarse con la API de Odoo.
 * Proporciona métodos de bajo nivel para:
 * - Autenticación (obtener UID)
 * - Operaciones CRUD (create, read, write, unlink)
 * - Búsquedas (search, search_read)
 *
 * Incluye reintentos automáticos ante errores de conexión (agotamiento de puertos TCP, timeouts).
 * Es la capa base que usan todos los repositorios de Odoo.
 */
@Component
public class OdooXmlRpcClient {

    private static final Logger log = LoggerFactory.getLogger(OdooXmlRpcClient.class);

    /** Número máximo de reintentos ante errores de conexión. */
    private static final int MAX_RETRIES = 3;
    /** Tiempo base de espera entre reintentos (ms). Se multiplica exponencialmente. */
    private static final long RETRY_BASE_DELAY_MS = 500;

    private final OdooConfig config;
    private final XmlRpcClient commonClient;
    private final XmlRpcClient objectClient;
    private Integer uid;
    private Integer defaultCompanyId;

    public OdooXmlRpcClient(OdooConfig config) {
        this.config = config;
        this.commonClient = createClient(config.getCommonEndpoint());
        this.objectClient = createClient(config.getObjectEndpoint());
    }

    private XmlRpcClient createClient(String endpoint) {
        XmlRpcClientConfigImpl clientConfig = new XmlRpcClientConfigImpl();
        try {
            clientConfig.setServerURL(new URL(endpoint));
        } catch (MalformedURLException e) {
            throw new OdooConnectionException("URL de Odoo inválida: " + endpoint, e);
        }
        // Timeouts para evitar conexiones colgadas
        clientConfig.setConnectionTimeout(30_000); // 30s para establecer conexión
        clientConfig.setReplyTimeout(120_000);      // 120s para esperar respuesta
        XmlRpcClient client = new XmlRpcClient();
        client.setConfig(clientConfig);
        return client;
    }

    /**
     * Autentica con Odoo y obtiene el UID del usuario.
     *
     * @return UID del usuario autenticado
     */
    public Integer authenticate() {
        if (uid != null) {
            return uid;
        }
        try {
            Object result = commonClient.execute("authenticate", Arrays.asList(
                    config.getDatabase(),
                    config.getUsername(),
                    config.getApikey(),
                    Collections.emptyMap()
            ));
            if (result instanceof Integer) {
                uid = (Integer) result;
                return uid;
            } else if (result instanceof Boolean && !(Boolean) result) {
                throw new OdooConnectionException("Credenciales de Odoo inválidas");
            }
            throw new OdooConnectionException("Respuesta de autenticación inesperada: " + result);
        } catch (XmlRpcException e) {
            throw new OdooConnectionException("Error al autenticar con Odoo", e);
        }
    }

    /**
     * Obtiene el ID de la empresa por defecto del usuario de la API (campo company_id de res.users).
     *
     * Se usa para acotar las sincronizaciones a esa empresa, ya que vía XML-RPC las búsquedas
     * devuelven registros de todas las compañías a las que el usuario tiene acceso (la interfaz
     * web sí filtra por la compañía activa, pero la API no). El valor se cachea tras la 1ª llamada.
     *
     * @return ID de la empresa por defecto, o null si no se pudo determinar
     */
    public Integer getDefaultCompanyId() {
        if (defaultCompanyId != null) {
            return defaultCompanyId;
        }
        Integer userId = authenticate();
        List<Map<String, Object>> result = read("res.users", List.of(userId), List.of("company_id"));
        if (!result.isEmpty() && result.get(0).get("company_id") instanceof Object[] arr && arr.length > 0) {
            defaultCompanyId = ((Number) arr[0]).intValue();
            String nombreEmpresa = arr.length > 1 ? String.valueOf(arr[1]) : "id=" + defaultCompanyId;
            log.info("[ODOO] Empresa por defecto del usuario de la API: {}", nombreEmpresa);
        } else {
            log.warn("[ODOO] No se pudo determinar la empresa por defecto del usuario de la API");
        }
        return defaultCompanyId;
    }

    /**
     * Ejecuta una operación en un modelo de Odoo.
     *
     * @param model  nombre del modelo (ej: "res.partner")
     * @param method método a ejecutar (ej: "create", "write", "search")
     * @param params parámetros del método
     * @return resultado de la operación
     */
    public Object execute(String model, String method, List<Object> params) {
        authenticate();
        for (int attempt = 1; attempt <= MAX_RETRIES; attempt++) {
            try {
                return objectClient.execute("execute_kw", Arrays.asList(
                        config.getDatabase(),
                        uid,
                        config.getApikey(),
                        model,
                        method,
                        params
                ));
            } catch (XmlRpcException e) {
                if (isConnectionError(e) && attempt < MAX_RETRIES) {
                    long delay = RETRY_BASE_DELAY_MS * (long) Math.pow(2, attempt - 1);
                    log.warn("[ODOO XML-RPC] Error de conexión en {}.{} (intento {}/{}), reintentando en {}ms: {}",
                            model, method, attempt, MAX_RETRIES, delay, e.getMessage());
                    sleep(delay);
                } else {
                    throw new OdooOperationException("Error ejecutando " + method + " en " + model + ": " + e.getMessage(), e);
                }
            }
        }
        throw new OdooOperationException("Error ejecutando " + method + " en " + model + " tras " + MAX_RETRIES + " intentos");
    }

    /**
     * Ejecuta una operación con parámetros adicionales (kwargs).
     *
     * @param model  nombre del modelo
     * @param method método a ejecutar
     * @param params parámetros posicionales
     * @param kwargs parámetros con nombre (ej: fields, limit)
     * @return resultado de la operación
     */
    public Object execute(String model, String method, List<Object> params, Map<String, Object> kwargs) {
        authenticate();
        for (int attempt = 1; attempt <= MAX_RETRIES; attempt++) {
            try {
                return objectClient.execute("execute_kw", Arrays.asList(
                        config.getDatabase(),
                        uid,
                        config.getApikey(),
                        model,
                        method,
                        params,
                        kwargs
                ));
            } catch (XmlRpcException e) {
                if (isConnectionError(e) && attempt < MAX_RETRIES) {
                    long delay = RETRY_BASE_DELAY_MS * (long) Math.pow(2, attempt - 1);
                    log.warn("[ODOO XML-RPC] Error de conexión en {}.{} (intento {}/{}), reintentando en {}ms: {}",
                            model, method, attempt, MAX_RETRIES, delay, e.getMessage());
                    sleep(delay);
                } else {
                    throw new OdooOperationException("Error ejecutando " + method + " en " + model + ": " + e.getMessage(), e);
                }
            }
        }
        throw new OdooOperationException("Error ejecutando " + method + " en " + model + " tras " + MAX_RETRIES + " intentos");
    }

    /**
     * Crea un registro en Odoo.
     *
     * @param model  nombre del modelo
     * @param values valores del registro
     * @return ID del registro creado
     */
    public Integer create(String model, Map<String, Object> values) {
        Object result = execute(model, "create", List.of(values));
        return (Integer) result;
    }

    /**
     * Actualiza un registro en Odoo.
     *
     * @param model  nombre del modelo
     * @param id     ID del registro
     * @param values valores a actualizar
     * @return true si se actualizó correctamente
     */
    public Boolean write(String model, Integer id, Map<String, Object> values) {
        Object result = execute(model, "write", Arrays.asList(List.of(id), values));
        return (Boolean) result;
    }

    /**
     * Elimina registros en Odoo.
     *
     * @param model nombre del modelo
     * @param ids   IDs de los registros a eliminar
     * @return true si se eliminaron correctamente
     */
    public Boolean unlink(String model, List<Integer> ids) {
        Object result = execute(model, "unlink", List.of(ids));
        return (Boolean) result;
    }

    /**
     * Busca IDs de registros que coincidan con el dominio.
     *
     * @param model  nombre del modelo
     * @param domain dominio de búsqueda (lista de condiciones)
     * @return lista de IDs encontrados
     */
    public List<Integer> search(String model, List<Object> domain) {
        Object[] result = (Object[]) execute(model, "search", List.of(domain));
        return Arrays.stream(result).map(o -> (Integer) o).toList();
    }

    /**
     * Busca y lee registros que coincidan con el dominio.
     *
     * @param model  nombre del modelo
     * @param domain dominio de búsqueda
     * @param fields campos a leer
     * @return lista de registros (cada uno es un Map)
     */
    @SuppressWarnings("unchecked")
    public List<Map<String, Object>> searchRead(String model, List<Object> domain, List<String> fields) {
        Object[] result = (Object[]) execute(
                model,
                "search_read",
                List.of(domain),
                buildReadKwargs(fields)
        );
        return Arrays.stream(result)
                .map(o -> (Map<String, Object>) o)
                .toList();
    }

    /**
     * Lee registros por sus IDs.
     *
     * @param model  nombre del modelo
     * @param ids    IDs de los registros
     * @param fields campos a leer
     * @return lista de registros
     */
    @SuppressWarnings("unchecked")
    public List<Map<String, Object>> read(String model, List<Integer> ids, List<String> fields) {
        Object[] result = (Object[]) execute(
                model,
                "read",
                List.of(ids),
                buildReadKwargs(fields)
        );
        return Arrays.stream(result)
                .map(o -> (Map<String, Object>) o)
                .toList();
    }

    /**
     * Verifica si existe un registro con el dominio especificado.
     *
     * @param model  nombre del modelo
     * @param domain dominio de búsqueda
     * @return true si existe al menos un registro
     */
    public boolean exists(String model, List<Object> domain) {
        List<Integer> ids = search(model, domain);
        return !ids.isEmpty();
    }

    /**
     * Busca un único registro por dominio.
     *
     * @param model  nombre del modelo
     * @param domain dominio de búsqueda
     * @return ID del registro o null si no existe
     */
    public Integer searchOne(String model, List<Object> domain) {
        List<Integer> ids = search(model, domain);
        return ids.isEmpty() ? null : ids.get(0);
    }

    /**
     * Construye los parámetros con nombre (kwargs) de las operaciones de lectura:
     * los campos a leer y, si está configurado, el idioma para los campos traducibles
     * (context = {lang: ...}), de modo que los nombres lleguen en español.
     */
    private Map<String, Object> buildReadKwargs(List<String> fields) {
        Map<String, Object> kwargs = new HashMap<>();
        kwargs.put("fields", fields);
        String lang = config.getLang();
        if (lang != null && !lang.isBlank()) {
            kwargs.put("context", Map.of("lang", lang));
        }
        return kwargs;
    }

    /**
     * Determina si un error XML-RPC es un error de conexión (agotamiento de puertos, timeout, etc.)
     * y por tanto se puede reintentar.
     */
    private boolean isConnectionError(XmlRpcException e) {
        String msg = e.getMessage();
        if (msg == null) {
            Throwable cause = e.getCause();
            msg = cause != null ? cause.getMessage() : "";
        }
        String msgLower = msg.toLowerCase();
        return msgLower.contains("address already in use")
                || msgLower.contains("connection refused")
                || msgLower.contains("connection reset")
                || msgLower.contains("failed to read server's response")
                || msgLower.contains("connect timed out")
                || msgLower.contains("read timed out")
                || msgLower.contains("broken pipe")
                || msgLower.contains("no route to host");
    }

    /**
     * Espera un tiempo (para reintentos con backoff).
     */
    private void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
        }
    }
}
