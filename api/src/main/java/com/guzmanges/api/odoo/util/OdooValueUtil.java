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

    /**
     * Convierte texto HTML básico (como el que devuelve Odoo en campos de tipo
     * {@code html}, p. ej. {@code sale.order.note}) a texto plano. Sustituye
     * las etiquetas de bloque más comunes por saltos de línea y elimina el
     * resto, deja también las entidades HTML básicas legibles.
     *
     * Lo bastante completo para una nota escrita por un comercial; no pretende
     * cubrir HTML arbitrario (Odoo no inserta scripts ni estilos en `note`).
     *
     * @param html texto con marcado HTML, o null
     * @return texto plano sin marcado, o null si el resultado queda vacío
     */
    public static String htmlAPlano(String html) {
        if (html == null) return null;
        String texto = html
                .replaceAll("(?i)<br\\s*/?>", "\n")
                .replaceAll("(?i)</p>", "\n")
                .replaceAll("(?i)</div>", "\n")
                .replaceAll("(?i)</li>", "\n")
                .replaceAll("<[^>]+>", "")
                .replace("&nbsp;", " ")
                .replace("&amp;", "&")
                .replace("&lt;", "<")
                .replace("&gt;", ">")
                .replace("&quot;", "\"")
                .replace("&#39;", "'")
                .trim();
        return texto.isEmpty() ? null : texto;
    }
}
