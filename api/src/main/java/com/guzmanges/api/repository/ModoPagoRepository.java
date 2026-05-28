package com.guzmanges.api.repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.guzmanges.api.entity.ModoPago;

public interface ModoPagoRepository extends JpaRepository<ModoPago, Long> {

    Optional<ModoPago> findByIdOdoo(String idOdoo);

    List<ModoPago> findByActivoTrueOrderByDescripcionAsc();

    /**
     * Lista todos los modos de pago (activos e inactivos) modificados desde la fecha indicada,
     * ordenados por descripción. Pensado para sincronizaciones incrementales.
     *
     * @param fechaDesde fecha de modificación mínima (inclusiva)
     * @return lista de modos de pago modificados a partir de esa fecha
     */
    List<ModoPago> findByFechaModificacionGreaterThanEqualOrderByDescripcionAsc(LocalDateTime fechaDesde);
}
