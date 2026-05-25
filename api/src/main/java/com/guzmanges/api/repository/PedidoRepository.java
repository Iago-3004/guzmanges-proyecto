package com.guzmanges.api.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.guzmanges.api.entity.EstadoSync;
import com.guzmanges.api.entity.Pedido;

public interface PedidoRepository extends JpaRepository<Pedido, Long> {

    List<Pedido> findByClienteIdOrderByFechaDesc(Long clienteId);

    Optional<Pedido> findByIdOdoo(String idOdoo);

    List<Pedido> findByEstadoSync(EstadoSync estadoSync);

    boolean existsByClienteId(Long clienteId);
}
