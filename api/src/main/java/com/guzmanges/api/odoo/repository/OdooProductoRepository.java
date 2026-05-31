package com.guzmanges.api.odoo.repository;

import java.math.BigDecimal;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.springframework.stereotype.Repository;

import com.guzmanges.api.odoo.client.OdooXmlRpcClient;

import lombok.RequiredArgsConstructor;

/**
 * Acceso a los productos de Odoo (modelo product.product).
 *
 * Solo lectura: los productos se gestionan en Odoo y se importan al backend
 * para que la app pueda cachearlos. No hay método create/update.
 */
@Repository
@RequiredArgsConstructor
public class OdooProductoRepository {

    private static final String MODEL = "product.product";
    private static final String TAX_MODEL = "account.tax";

    /** Campos que se leen de cada producto de Odoo. */
    private static final List<String> FIELDS = List.of(
            "id", "default_code", "name", "barcode", "type", "qty_available",
            "lst_price", "description_sale", "taxes_id", "write_date", "active");

    private final OdooXmlRpcClient client;

    /**
     * Obtiene los productos vendibles de Odoo (sale_ok = true) de la empresa por
     * defecto del usuario de la API más los compartidos. Incluye los archivados
     * para que la app pueda detectar bajas.
     *
     * @return lista de registros de Odoo
     */
    public List<Map<String, Object>> findProductos() {
        Integer companyId = client.getDefaultCompanyId();
        List<Object> domain;
        if (companyId != null) {
            domain = List.of(
                    "|",
                    Arrays.asList("company_id", "=", companyId),
                    Arrays.asList("company_id", "=", false),
                    Arrays.asList("sale_ok", "=", true),
                    Arrays.asList("active", "in", List.of(true, false))
            );
        } else {
            domain = List.of(
                    Arrays.asList("sale_ok", "=", true),
                    Arrays.asList("active", "in", List.of(true, false))
            );
        }
        return client.searchRead(MODEL, domain, FIELDS);
    }

    /**
     * De una lista de ids, devuelve los que todavía existen como product.product
     * en Odoo (activos o archivados). Igual que para clientes: se usa para
     * confirmar borrados reales (un id que NO vuelve ha sido eliminado por
     * completo en Odoo).
     *
     * @param ids ids de Odoo a comprobar
     * @return conjunto de ids que siguen existiendo
     */
    public Set<Integer> findExistingIds(List<Integer> ids) {
        if (ids == null || ids.isEmpty()) {
            return Set.of();
        }
        List<Object> domain = List.of(
                Arrays.asList("id", "in", ids),
                Arrays.asList("active", "in", List.of(true, false))
        );
        return new HashSet<>(client.search(MODEL, domain));
    }

    /**
     * Lee de Odoo el porcentaje de IVA de un conjunto de impuestos (account.tax)
     * en una sola llamada. Devuelve un mapa id → amount.
     *
     * Pensado para resolver de un golpe el IVA por defecto de todos los productos
     * importados, evitando una llamada XML-RPC por cada producto. Solo se queda
     * con los impuestos de venta (type_tax_use = "sale") para descartar los de
     * compra que pueda llevar el mismo producto.
     *
     * @param ids ids de los account.tax a consultar
     * @return mapa idTax → porcentaje (BigDecimal); vacío si la lista es vacía
     */
    public Map<Integer, BigDecimal> findTaxAmounts(Set<Integer> ids) {
        Map<Integer, BigDecimal> resultado = new HashMap<>();
        if (ids == null || ids.isEmpty()) {
            return resultado;
        }
        List<Object> domain = List.of(
                Arrays.asList("id", "in", List.copyOf(ids)),
                Arrays.asList("type_tax_use", "=", "sale")
        );
        List<Map<String, Object>> filas = client.searchRead(
                TAX_MODEL, domain, List.of("id", "amount"));
        for (Map<String, Object> fila : filas) {
            Integer id = ((Number) fila.get("id")).intValue();
            Object amount = fila.get("amount");
            if (amount instanceof Number n) {
                resultado.put(id, BigDecimal.valueOf(n.doubleValue()));
            }
        }
        return resultado;
    }
}
