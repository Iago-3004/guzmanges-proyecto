package com.guzmanges.api.odoo.exception;

/**
 * Excepción para errores de conexión con Odoo.
 * Se lanza cuando hay problemas de autenticación, red o comunicación XML-RPC.
 */
public class OdooConnectionException extends RuntimeException {

    public OdooConnectionException(String message) {
        super(message);
    }

    public OdooConnectionException(String message, Throwable cause) {
        super(message, cause);
    }
}
