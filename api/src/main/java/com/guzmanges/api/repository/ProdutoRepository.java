package com.guzmanges.api.repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.guzmanges.api.entity.Produto;

public interface ProdutoRepository extends JpaRepository<Produto, Long> {

    Optional<Produto> findByIdOdoo(String idOdoo);

    /**
     * Lista todos los productos, ordenados por descripción.
     *
     * @return lista completa de productos
     */
    List<Produto> findAllByOrderByDescripcionAsc();

    /**
     * Lista los productos modificados desde la fecha indicada, ordenados por descripción.
     * Pensado para sincronizaciones incrementales: la app así detecta cambios de stock,
     * precios o bajas desde la última sincronización.
     *
     * @param fechaDesde fecha de modificación mínima (inclusiva)
     * @return lista de productos modificados a partir de esa fecha
     */
    List<Produto> findByFechaModificacionGreaterThanEqualOrderByDescripcionAsc(LocalDateTime fechaDesde);
}
