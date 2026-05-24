package com.guzmanges.api.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.guzmanges.api.entity.Cliente;
import com.guzmanges.api.entity.EstadoSync;

public interface ClienteRepository extends JpaRepository<Cliente, Long> {

    Optional<Cliente> findByIdOdoo(String idOdoo);

    List<Cliente> findByIdOdooIsNull();

    List<Cliente> findByEstadoSync(EstadoSync estadoSync);

    List<Cliente> findByActivoTrueOrderByNombreComercialAsc();

    List<Cliente> findByCifIgnoreCase(String cif);
}
