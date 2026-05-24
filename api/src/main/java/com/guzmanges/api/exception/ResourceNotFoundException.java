package com.guzmanges.api.exception;

/**
 * Se lanza cuando no se encuentra un recurso solicitado.
 * El manejador global la traduce a una respuesta HTTP 404.
 */
public class ResourceNotFoundException extends RuntimeException {

    public ResourceNotFoundException(String message) {
        super(message);
    }
}
