package com.guzmanges.api.repository;

import org.springframework.data.jpa.repository.JpaRepository;

import com.guzmanges.api.entity.LineaPedido;

public interface LineaPedidoRepository extends JpaRepository<LineaPedido, Long> {

    /**
     * Indica si un producto está referenciado por alguna línea de pedido.
     * Se usa en la reconciliación de borrados desde Odoo: si Odoo borra un
     * producto que figura en pedidos históricos, se conserva en la BD local
     * en vez de borrarse, para no romper la integridad referencial ni perder
     * el dato histórico.
     *
     * @param productoId id del producto
     * @return true si existe al menos una línea con ese producto
     */
    boolean existsByProductoId(Long productoId);
}
