package com.guzmanges.api.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

import com.guzmanges.api.entity.EstadoPedido;
import com.guzmanges.api.entity.EstadoSync;

/**
 * Datos de un pedido tal como los recibe la app.
 *
 * Incluye un resumen embebido del cliente (id y razón social) para que la lista
 * pueda pintar el nombre sin tener que hacer un fetch adicional. Las líneas
 * llegan completas.
 *
 * Los totales son provisionales hasta que Odoo confirme el pedido: en ese
 * momento el backend los sobrescribe con los definitivos que devuelve
 * {@code sale.order} aplicando la posición fiscal del cliente.
 */
public record PedidoResponse(
        Long id,
        String idOdoo,
        String numero,
        LocalDateTime fecha,
        EstadoPedido estadoPedido,
        EstadoSync estadoSync,
        ClienteResumen cliente,
        String usuario,
        List<LineaResponse> lineas,
        BigDecimal totalBase,
        BigDecimal totalIva,
        BigDecimal totalRE,
        BigDecimal total,
        LocalDateTime fechaModificacion
) {
    /**
     * Resumen mínimo del cliente que viaja con cada pedido, suficiente para
     * pintar la lista sin volver a consultar al servidor.
     */
    public record ClienteResumen(Long id, String razonSocial) {}
}
