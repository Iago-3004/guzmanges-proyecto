package com.guzmanges.api.odoo.service;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.guzmanges.api.entity.Produto;
import com.guzmanges.api.odoo.mapper.OdooProductoMapper;
import com.guzmanges.api.odoo.repository.OdooProductoRepository;
import com.guzmanges.api.repository.LineaPedidoRepository;
import com.guzmanges.api.repository.ProdutoRepository;

import lombok.RequiredArgsConstructor;

/**
 * Servicio de sincronización del catálogo de productos con Odoo.
 *
 * Odoo es la fuente de verdad: los productos solo se importan (Odoo → MySQL),
 * nunca se envían en sentido contrario. Para cada registro de Odoo se busca el
 * equivalente local por su idOdoo; si existe se actualiza cuando hay cambios y
 * si no existe se crea. Al terminar, se reconcilian los borrados: los productos
 * locales con idOdoo que ya no aparecen en Odoo se eliminan, salvo que estén
 * referenciados por alguna línea de pedido (histórico que se debe preservar).
 */
@Service
@RequiredArgsConstructor
public class OdooProductosSyncService {

    private static final Logger log = LoggerFactory.getLogger(OdooProductosSyncService.class);

    private final ProdutoRepository produtoRepository;
    private final LineaPedidoRepository lineaPedidoRepository;
    private final OdooProductoRepository odooProductoRepository;
    private final OdooProductoMapper odooProductoMapper;

    /**
     * Importa el catálogo de productos desde Odoo a la BD local. Decide si cada
     * producto es nuevo, una actualización o ya está sincronizado, y reconcilia
     * los borrados al final.
     *
     * @return número de productos creados o actualizados (no incluye sinCambios)
     */
    @Transactional
    public int importarProductosDesdeOdoo() {
        log.info("=== IMPORTANDO PRODUCTOS DESDE ODOO ===");
        List<Map<String, Object>> productosOdoo = odooProductoRepository.findProductos();
        log.info("Productos encontrados en Odoo: {}", productosOdoo.size());

        // Pre-resuelve los porcentajes de IVA: recoge todos los ids de taxes_id
        // que aparecen en los productos y los consulta de un golpe a Odoo. Así
        // se evita una llamada XML-RPC por producto.
        Map<Integer, BigDecimal> ivaPorTaxId = cargarPorcentajesIva(productosOdoo);

        int nuevos = 0;
        int actualizados = 0;
        int sinCambios = 0;
        Set<String> idsVistos = new HashSet<>();
        for (Map<String, Object> datosOdoo : productosOdoo) {
            try {
                String idOdoo = String.valueOf(((Number) datosOdoo.get("id")).longValue());
                idsVistos.add(idOdoo);
                Produto desdeOdoo = odooProductoMapper.fromOdooToProduto(datosOdoo, ivaPorTaxId::get);

                Optional<Produto> existente = produtoRepository.findByIdOdoo(idOdoo);
                if (existente.isPresent()) {
                    Produto producto = existente.get();
                    if (mismosCampos(producto, desdeOdoo)) {
                        sinCambios++;
                        continue;
                    }
                    copiarDatosDeOdoo(producto, desdeOdoo);
                    produtoRepository.save(producto);
                    actualizados++;
                } else {
                    produtoRepository.save(desdeOdoo);
                    nuevos++;
                    log.info("[ODOO -> DB] Nuevo producto: {} (idOdoo: {})",
                            desdeOdoo.getDescripcion(), idOdoo);
                }
            } catch (Exception e) {
                log.error("[ODOO -> DB] Error importando producto idOdoo={}: {}",
                        datosOdoo.get("id"), e.getMessage());
            }
        }

        log.info("=== PRODUCTOS: {} nuevos, {} actualizados, {} sin cambios (de {} en Odoo) ===",
                nuevos, actualizados, sinCambios, productosOdoo.size());

        reconciliarProductosBorrados(idsVistos);
        return nuevos + actualizados;
    }

    /**
     * Recoge todos los ids de impuesto presentes en {@code taxes_id} de los
     * productos y los traduce a porcentajes en una sola llamada a Odoo.
     */
    private Map<Integer, BigDecimal> cargarPorcentajesIva(List<Map<String, Object>> productosOdoo) {
        Set<Integer> taxIds = new HashSet<>();
        for (Map<String, Object> producto : productosOdoo) {
            Object raw = producto.get("taxes_id");
            if (raw instanceof Object[] arr) {
                for (Object id : arr) {
                    if (id instanceof Number n) {
                        taxIds.add(n.intValue());
                    }
                }
            }
        }
        return odooProductoRepository.findTaxAmounts(taxIds);
    }

    /**
     * Detecta y procesa los productos borrados por completo en Odoo. Un producto
     * local con idOdoo cuyo id no figura entre los vistos en la importación es un
     * candidato; se confirma consultando a Odoo si ese id todavía existe (un
     * producto archivado SÍ se devuelve, no es un borrado real). Los confirmados
     * como borrados se eliminan de MySQL, salvo que tengan líneas de pedido
     * asociadas: en ese caso se conservan para no romper el histórico.
     */
    private void reconciliarProductosBorrados(Set<String> idsVistos) {
        List<Produto> candidatos = produtoRepository.findAll().stream()
                .filter(p -> p.getIdOdoo() != null && !idsVistos.contains(p.getIdOdoo()))
                .toList();
        if (candidatos.isEmpty()) {
            return;
        }

        List<Integer> idsCandidatos = candidatos.stream()
                .map(p -> Integer.parseInt(p.getIdOdoo()))
                .toList();
        Set<Integer> existentes = odooProductoRepository.findExistingIds(idsCandidatos);

        int borrados = 0;
        int conservados = 0;
        for (Produto producto : candidatos) {
            if (existentes.contains(Integer.parseInt(producto.getIdOdoo()))) {
                continue;
            }
            if (lineaPedidoRepository.existsByProductoId(producto.getId())) {
                conservados++;
                log.warn("[ODOO -> DB] Producto '{}' (idOdoo {}) borrado en Odoo pero tiene líneas de pedido: "
                        + "se conserva en la BD local", producto.getDescripcion(), producto.getIdOdoo());
            } else {
                produtoRepository.delete(producto);
                borrados++;
                log.info("[ODOO -> DB] Producto '{}' (idOdoo {}) borrado en Odoo: eliminado de MySQL",
                        producto.getDescripcion(), producto.getIdOdoo());
            }
        }

        if (borrados > 0 || conservados > 0) {
            log.info("=== RECONCILIACIÓN DE BORRADOS: {} eliminados, {} conservados (con histórico) ===",
                    borrados, conservados);
        }
    }

    /**
     * Comprueba si el producto local ya refleja los datos recién traídos de Odoo.
     * Si todos los campos comparados coinciden, no merece la pena hacer un save
     * (que dispararía un cambio de fechaModificacion y propagaría una falsa
     * actualización a las apps).
     */
    private boolean mismosCampos(Produto local, Produto desdeOdoo) {
        return java.util.Objects.equals(local.getDescripcion(), desdeOdoo.getDescripcion())
                && java.util.Objects.equals(local.getReferencia(), desdeOdoo.getReferencia())
                && java.util.Objects.equals(local.getCodigoBarras(), desdeOdoo.getCodigoBarras())
                && java.util.Objects.equals(local.getTipoProduto(), desdeOdoo.getTipoProduto())
                && java.util.Objects.equals(local.getStock(), desdeOdoo.getStock())
                && compararBigDecimal(local.getPrecioVenta(), desdeOdoo.getPrecioVenta())
                && compararBigDecimal(local.getIva(), desdeOdoo.getIva())
                && java.util.Objects.equals(local.getObservaciones(), desdeOdoo.getObservaciones());
    }

    /**
     * Compara dos BigDecimal por valor numérico, no por escala. {@code BigDecimal.equals}
     * distingue 21 de 21.00 y rompería la comparación. Cualquiera de los dos puede ser null.
     */
    private boolean compararBigDecimal(BigDecimal a, BigDecimal b) {
        if (a == null && b == null) return true;
        if (a == null || b == null) return false;
        return a.compareTo(b) == 0;
    }

    /**
     * Vuelca los datos de un producto recién leído de Odoo sobre el ya guardado
     * en local. No toca el id local ni el idOdoo (que ya está fijado) y refresca
     * la marca temporal para que la app reciba el cambio en la próxima sync.
     */
    private void copiarDatosDeOdoo(Produto destino, Produto desdeOdoo) {
        destino.setReferencia(desdeOdoo.getReferencia());
        destino.setCodigoBarras(desdeOdoo.getCodigoBarras());
        destino.setDescripcion(desdeOdoo.getDescripcion());
        destino.setTipoProduto(desdeOdoo.getTipoProduto());
        destino.setStock(desdeOdoo.getStock());
        destino.setPrecioVenta(desdeOdoo.getPrecioVenta());
        destino.setIva(desdeOdoo.getIva());
        destino.setObservaciones(desdeOdoo.getObservaciones());
        destino.setFechaModificacion(LocalDateTime.now());
    }
}
