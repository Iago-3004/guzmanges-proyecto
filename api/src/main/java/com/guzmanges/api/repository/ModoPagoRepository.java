package com.guzmanges.api.repository;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.guzmanges.api.entity.ModoPago;

public interface ModoPagoRepository extends JpaRepository<ModoPago, Long> {

    Optional<ModoPago> findByIdOdoo(String idOdoo);
}
