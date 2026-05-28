package com.guzmanges.api.repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.guzmanges.api.entity.CondicionPago;

public interface CondicionPagoRepository extends JpaRepository<CondicionPago, Long> {

    Optional<CondicionPago> findByIdOdoo(String idOdoo);

    List<CondicionPago> findByActivoTrueOrderByDescripcionAsc();

    /**
     * Lista todas las condiciones de pago (activas e inactivas) modificadas desde la fecha
     * indicada, ordenadas por descripción. Pensado para sincronizaciones incrementales.
     *
     * @param fechaDesde fecha de modificación mínima (inclusiva)
     * @return lista de condiciones de pago modificadas a partir de esa fecha
     */
    List<CondicionPago> findByFechaModificacionGreaterThanEqualOrderByDescripcionAsc(LocalDateTime fechaDesde);
}
