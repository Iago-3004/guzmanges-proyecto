package com.guzmanges.api.util;

/**
 * Utilidad para formatear CIF/NIF/VAT.
 * Centraliza la lógica de formateo que se usa en la sincronización con Odoo.
 */
public final class VatUtil {

    private VatUtil() {
        // Clase de utilidad, no instanciable
    }

    /**
     * Formatea el CIF/NIF para Odoo (añade prefijo "ES" si no lo tiene).
     *
     * @param cif CIF/NIF del cliente
     * @return CIF formateado con prefijo de país, o null si es vacío
     */
    public static String formatVat(String cif) {
        if (cif == null || cif.isEmpty()) {
            return null;
        }
        // Si ya tiene prefijo de país (2 letras al inicio), lo devolvemos tal cual
        if (cif.length() > 2 && Character.isLetter(cif.charAt(0)) && Character.isLetter(cif.charAt(1))) {
            return cif.toUpperCase();
        }
        // Añadir prefijo ES para España
        return "ES" + cif.toUpperCase();
    }
}
