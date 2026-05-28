package com.guzmanges.api.repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.guzmanges.api.entity.Cliente;
import com.guzmanges.api.entity.EstadoSync;

public interface ClienteRepository extends JpaRepository<Cliente, Long> {

    Optional<Cliente> findByIdOdoo(String idOdoo);

    List<Cliente> findByIdOdooIsNull();

    List<Cliente> findByIdOdooIsNotNull();

    List<Cliente> findByEstadoSync(EstadoSync estadoSync);

    List<Cliente> findByActivoTrueOrderByNombreComercialAsc();

    /**
     * Lista todos los clientes (activos e inactivos) modificados desde la fecha indicada,
     * ordenados por nombre comercial. Pensado para sincronizaciones incrementales:
     * la app así detecta también los clientes desactivados desde la última sincronización.
     *
     * @param fechaDesde fecha de modificación mínima (inclusiva)
     * @return lista de clientes modificados a partir de esa fecha
     */
    List<Cliente> findByFechaModificacionGreaterThanEqualOrderByNombreComercialAsc(LocalDateTime fechaDesde);

    List<Cliente> findByCifIgnoreCase(String cif);
}
