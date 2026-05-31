package com.guzmanges.api.odoo.mapper;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Map;
import java.util.function.Function;

import org.springframework.stereotype.Component;

import com.guzmanges.api.entity.Produto;
import com.guzmanges.api.odoo.util.OdooValueUtil;

/**
 * Conversión entre la entidad {@link Produto} y el modelo product.product de Odoo.
 *
 * Los productos son de solo lectura: este mapper construye la entidad local a
 * partir de los datos de Odoo. No hay sentido contrario.
 */
@Component
public class OdooProductoMapper {

    /**
     * Construye una entidad {@link Produto} a partir de un registro de Odoo.
     *
     * @param odooData    datos del producto en Odoo (search_read)
     * @param ivaResolver función que, dado el id de un account.tax de Odoo,
     *                    devuelve su porcentaje (o null si no se conoce).
     *                    El llamante precarga estos porcentajes en bloque para
     *                    no consultar Odoo línea a línea.
     * @return el producto con todos los campos rellenados; fechaModificacion = now()
     */
    public Produto fromOdooToProduto(Map<String, Object> odooData,
                                     Function<Integer, BigDecimal> ivaResolver) {
        Produto produto = new Produto();
        produto.setIdOdoo(String.valueOf(((Number) odooData.get("id")).longValue()));
        produto.setReferencia(OdooValueUtil.getStringValue(odooData, "default_code"));
        produto.setCodigoBarras(OdooValueUtil.getStringValue(odooData, "barcode"));

        String nombre = OdooValueUtil.getStringValue(odooData, "name");
        produto.setDescripcion(nombre != null ? nombre : "Sin descripción");

        produto.setTipoProduto(OdooValueUtil.getStringValue(odooData, "type"));
        produto.setObservaciones(OdooValueUtil.getStringValue(odooData, "description_sale"));

        Object stockRaw = odooData.get("qty_available");
        if (stockRaw instanceof Number n) {
            produto.setStock(n.intValue());
        }

        Object precioRaw = odooData.get("lst_price");
        if (precioRaw instanceof Number n) {
            produto.setPrecioVenta(BigDecimal.valueOf(n.doubleValue()));
        }

        // IVA: en Odoo cada producto puede tener varios impuestos (taxes_id), pero
        // en venta minorista habitual hay un único IVA por defecto. Cogemos el
        // primero que el resolver sepa traducir a porcentaje; si no hay ninguno,
        // queda null y la app lo trata como 0 % al construir líneas (raro pero
        // posible: productos exentos sin impuesto asignado).
        produto.setIva(resolverIva(odooData, ivaResolver));

        produto.setFechaModificacion(LocalDateTime.now());
        return produto;
    }

    /**
     * Recorre los ids de {@code taxes_id} del producto y devuelve el primero
     * cuyo porcentaje conozca el resolver. Mantiene un comportamiento estable
     * si Odoo añade impuestos auxiliares (p. ej. ecotasa) que aún no estén en
     * la cache de impuestos cargada por el servicio.
     */
    private BigDecimal resolverIva(Map<String, Object> odooData,
                                   Function<Integer, BigDecimal> ivaResolver) {
        Object taxesRaw = odooData.get("taxes_id");
        if (!(taxesRaw instanceof Object[] arr) || ivaResolver == null) {
            return null;
        }
        for (Object idRaw : arr) {
            if (idRaw instanceof Number n) {
                BigDecimal amount = ivaResolver.apply(n.intValue());
                if (amount != null) {
                    return amount;
                }
            }
        }
        return null;
    }
}
