package com.guzmanges.api.exception;

/**
 * Indica que un alta o edición de usuario chocaría con otro existente:
 * el {@code nombreUsuario} o el {@code email} ya están en uso. Se traduce
 * a HTTP 409 en el {@code GlobalExceptionHandler}, indicando además qué
 * campo provoca el conflicto para que la pantalla de gestión muestre el
 * mensaje en el formulario correcto.
 */
public class UsuarioDuplicadoException extends RuntimeException {

    private final String campo;

    public UsuarioDuplicadoException(String campo, String mensaje) {
        super(mensaje);
        this.campo = campo;
    }

    public String getCampo() {
        return campo;
    }
}
