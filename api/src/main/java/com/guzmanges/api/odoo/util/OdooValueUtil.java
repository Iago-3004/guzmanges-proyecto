package com.guzmanges.api.odoo.util;

import java.util.Map;

/**
 * Utilidades para trabajar con datos de Odoo recibidos vía XML-RPC.
 * Odoo (Python) usa el valor "false" (como String) para representar campos vacíos,
 * por lo que es necesario tratarlo como null en Java.
 */
public final class OdooValueUtil {

    private OdooValueUtil() {
        // Clase de utilidad, no instanciable
    }

    /**
     * Extrae un String de un Map de datos de Odoo.
     * Trata el valor "false" de Python y los Strings vacíos como null.
     *
     * @param data Map con los datos del registro de Odoo
     * @param key  clave del campo a extraer
     * @return el valor como String, o null si es "false", vacío o no es un String
     */
    public static String getStringValue(Map<String, Object> data, String key) {
        Object value = data.get(key);
        if (value instanceof String strValue && !"false".equals(strValue) && !strValue.isEmpty()) {
            return strValue;
        }
        return null;
    }
}
