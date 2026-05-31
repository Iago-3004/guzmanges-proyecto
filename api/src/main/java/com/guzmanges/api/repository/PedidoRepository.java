package com.guzmanges.api.repository;

import java.time.LocalDateTime;
import java.util.Collection;
import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.guzmanges.api.entity.EstadoSync;
import com.guzmanges.api.entity.Pedido;
import com.guzmanges.api.entity.Usuario;

public interface PedidoRepository extends JpaRepository<Pedido, Long> {

    List<Pedido> findByClienteIdOrderByFechaDesc(Long clienteId);

    Optional<Pedido> findByIdOdoo(String idOdoo);

    List<Pedido> findByEstadoSync(EstadoSync estadoSync);

    /**
     * Lista los pedidos en cualquiera de los estados de sincronización dados.
     * El scheduler de envío a Odoo lo usa para reintentar PENDENTE + ERRO en
     * la misma vuelta: los errores típicos de pedidos son transitorios
     * (cliente sin sincronizar, Odoo caído, bug puntual) y se recuperan solos
     * en el siguiente tic sin intervención manual.
     */
    List<Pedido> findByEstadoSyncIn(Collection<EstadoSync> estados);

    boolean existsByClienteId(Long clienteId);

    /**
     * Lista todos los pedidos de un preventa, ordenados de más reciente a más
     * antiguo. Pensado para la lista principal de pedidos en la app.
     *
     * @param usuario preventa al que pertenecen los pedidos
     * @return lista de pedidos del usuario, descendente por fecha
     */
    List<Pedido> findByUsuarioOrderByFechaDesc(Usuario usuario);

    /**
     * Lista los pedidos de un preventa modificados desde una fecha dada,
     * ordenados de más reciente a más antiguo. Pensado para la sincronización
     * incremental: la app pide solo lo que cambió en el servidor (por ejemplo,
     * un pedido confirmado por Odoo o anulado).
     *
     * @param fechaDesde fecha de modificación mínima (inclusiva)
     * @param usuario    preventa al que pertenecen los pedidos
     * @return lista de pedidos modificados, descendente por fecha
     */
    List<Pedido> findByFechaModificacionGreaterThanEqualAndUsuarioOrderByFechaDesc(
            LocalDateTime fechaDesde, Usuario usuario);

    /**
     * Lista todos los pedidos modificados desde una fecha dada, sin filtrar por
     * preventa. Pensado para usuarios ADMIN.
     *
     * @param fechaDesde fecha de modificación mínima (inclusiva)
     * @return lista de pedidos modificados, descendente por fecha
     */
    List<Pedido> findByFechaModificacionGreaterThanEqualOrderByFechaDesc(LocalDateTime fechaDesde);

    /**
     * Lista todos los pedidos, descendente por fecha. Para usuarios ADMIN que
     * quieren ver la cartera completa sin filtro.
     */
    List<Pedido> findAllByOrderByFechaDesc();
}
