package com.guzmanges.api.exception;

import java.util.List;

import com.guzmanges.api.dto.ClienteResponse;

/**
 * Se lanza al dar de alta un cliente cuyo CIF ya existe en la base de datos local.
 * Lleva la lista de clientes existentes con ese CIF para que la app pueda mostrarlos
 * y el usuario decida si crear uno nuevo de todas formas (forzarAlta=true).
 */
public class CifDuplicadoException extends RuntimeException {

    private final transient List<ClienteResponse> existentes;

    public CifDuplicadoException(String message, List<ClienteResponse> existentes) {
        super(message);
        this.existentes = existentes;
    }

    public List<ClienteResponse> getExistentes() {
        return existentes;
    }
}
