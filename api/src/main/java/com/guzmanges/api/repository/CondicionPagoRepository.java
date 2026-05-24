package com.guzmanges.api.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.guzmanges.api.entity.CondicionPago;

public interface CondicionPagoRepository extends JpaRepository<CondicionPago, Long> {

    Optional<CondicionPago> findByIdOdoo(String idOdoo);

    List<CondicionPago> findByActivoTrueOrderByDescripcionAsc();
}
