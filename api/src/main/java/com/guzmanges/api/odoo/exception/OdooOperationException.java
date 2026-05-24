package com.guzmanges.api.odoo.exception;

/**
 * Excepción para errores en operaciones de Odoo.
 * Se lanza cuando falla una operación CRUD o hay errores de validación en Odoo.
 */
public class OdooOperationException extends RuntimeException {

    public OdooOperationException(String message) {
        super(message);
    }

    public OdooOperationException(String message, Throwable cause) {
        super(message, cause);
    }
}
