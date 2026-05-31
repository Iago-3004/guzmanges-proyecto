package com.guzmanges.api.odoo.service;

import java.util.ArrayList;
import java.util.List;

/**
 * Resultado de una sincronización: cuántos registros se procesaron correctamente
 * y el detalle de los que fallaron.
 */
public class SyncResult {

    private int exitos = 0;
    private final List<String> detalles = new ArrayList<>();

    public void addExito() {
        exitos++;
    }

    public void addError(Long id, String mensaje) {
        addError("Cliente", id, mensaje);
    }

    /**
     * Registra un error con un prefijo personalizado (p. ej. "Pedido"), para que
     * el mismo {@link SyncResult} sirva tanto al envío de clientes como al de
     * pedidos sin que el detalle quede etiquetado siempre como "Cliente".
     */
    public void addError(String prefijo, Long id, String mensaje) {
        detalles.add(prefijo + " " + id + ": " + mensaje);
    }

    public int getExitos() {
        return exitos;
    }

    public int getErrores() {
        return detalles.size();
    }

    public List<String> getDetalles() {
        return detalles;
    }

    public int getTotal() {
        return exitos + detalles.size();
    }

    @Override
    public String toString() {
        return exitos + " correctos, " + detalles.size() + " con error";
    }
}
