package com.guzmanges.api.dto;

import java.util.List;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;

/**
 * Pedido recibido desde la app para crear en la BD local del backend.
 *
 * El pedido queda con {@code estadoPedido = BORRADOR} y {@code estadoSync = PENDENTE}
 * tras la creación; los totales se calculan en el servidor a partir de las líneas
 * y se sobrescriben con los definitivos cuando Odoo confirme el pedido.
 */
public record CrearPedidoRequest(

        @NotNull(message = "El cliente es obligatorio")
        Long clienteId,

        @NotEmpty(message = "El pedido debe tener al menos una línea")
        @Valid
        List<CrearLineaRequest> lineas
) {
}
