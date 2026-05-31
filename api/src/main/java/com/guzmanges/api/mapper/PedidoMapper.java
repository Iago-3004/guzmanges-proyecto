package com.guzmanges.api.mapper;

import org.springframework.stereotype.Component;

import com.guzmanges.api.dto.LineaResponse;
import com.guzmanges.api.dto.PedidoResponse;
import com.guzmanges.api.entity.LineaPedido;
import com.guzmanges.api.entity.Pedido;

/**
 * Conversión de las entidades {@link Pedido} y {@link LineaPedido} a sus DTOs
 * de respuesta. El resumen del cliente y el login del comercial se anidan en
 * el response para que la app no tenga que volver a pedirlos.
 */
@Component
public class PedidoMapper {

    public PedidoResponse toResponse(Pedido pedido) {
        return new PedidoResponse(
                pedido.getId(),
                pedido.getIdOdoo(),
                pedido.getNumero(),
                pedido.getFecha(),
                pedido.getEstadoPedido(),
                pedido.getEstadoSync(),
                new PedidoResponse.ClienteResumen(
                        pedido.getCliente().getId(),
                        pedido.getCliente().getRazonSocial()
                ),
                pedido.getUsuario().getNombreUsuario(),
                pedido.getLineas().stream().map(this::toResponse).toList(),
                pedido.getTotalBase(),
                pedido.getTotalIva(),
                pedido.getTotalRE(),
                pedido.getTotal(),
                pedido.getFechaModificacion()
        );
    }

    public LineaResponse toResponse(LineaPedido linea) {
        return new LineaResponse(
                linea.getId(),
                linea.getProducto() != null ? linea.getProducto().getId() : null,
                linea.getCodigoProducto(),
                linea.getDescripcion(),
                linea.getPrecio(),
                linea.getIva(),
                linea.getRecargoEquivalencia(),
                linea.getCantidade(),
                linea.getSubtotal()
        );
    }
}
