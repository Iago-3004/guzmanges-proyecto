package com.guzmanges.api.odoo.repository;

import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.springframework.stereotype.Repository;

import com.guzmanges.api.entity.LineaPedido;
import com.guzmanges.api.entity.Pedido;
import com.guzmanges.api.odoo.client.OdooXmlRpcClient;

import lombok.RequiredArgsConstructor;

/**
 * Acceso a los pedidos de venta de Odoo (modelo {@code sale.order}).
 *
 * Solo se utiliza para enviar pedidos creados en la app y para volver a leerlos
 * inmediatamente después: el servidor escribe los totales provisionales con los
 * definitivos que devuelve Odoo (aplicando la posición fiscal del cliente).
 *
 * Los pedidos NO se importan en sentido contrario: la app es la única fuente
 * de altas de pedidos.
 */
@Repository
@RequiredArgsConstructor
public class OdooPedidoRepository {

    private static final String MODEL = "sale.order";
    private static final String MODEL_LINEA = "sale.order.line";

    /**
     * Campos mínimos que se leen tras crear el pedido: número y totales.
     * Suficiente para sobrescribir los provisionales en MySQL.
     */
    private static final List<String> FIELDS = List.of(
            "id", "name", "amount_untaxed", "amount_tax", "amount_total");

    /**
     * Campos completos para la importación periódica Odoo → MySQL: incluyen
     * además partner, vendedor, fecha, estado, líneas y write_date.
     */
    private static final List<String> FIELDS_COMPLETO = List.of(
            "id", "name", "partner_id", "user_id", "date_order", "state",
            "amount_untaxed", "amount_tax", "amount_total", "order_line",
            "note", "write_date");

    /**
     * Campos por línea ({@code sale.order.line}) suficientes para reconstruir
     * la línea en local: producto, cantidad, precio y subtotal/total.
     * {@code display_type} se lee para descartar las "líneas de sección" o
     * "líneas de nota" que no representan un producto vendido.
     */
    private static final List<String> FIELDS_LINEA = List.of(
            "id", "order_id", "product_id", "product_uom_qty",
            "price_unit", "price_subtotal", "price_total", "name", "display_type");

    /**
     * Formato que Odoo espera para los campos Datetime ({@code yyyy-MM-dd HH:mm:ss}).
     * No admite fracciones de segundo: {@code LocalDateTime.toString()} las añade
     * cuando hay nanos > 0 y Odoo rechaza la cadena con "unconverted data remains".
     */
    private static final DateTimeFormatter ODOO_DATETIME = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final OdooXmlRpcClient client;

    /**
     * Crea un pedido en Odoo. No se envían totales ni subtotales: los calcula
     * Odoo a partir de las líneas, los impuestos del producto y la posición
     * fiscal del cliente.
     *
     * @param pedido        pedido local con sus líneas resueltas
     * @param partnerOdooId id del cliente en Odoo ({@code res.partner})
     * @param userOdooId    id del comercial en Odoo ({@code res.users}), o null
     *                      para no asignar vendedor
     * @return id del {@code sale.order} creado
     */
    public Integer create(Pedido pedido, Integer partnerOdooId, Integer userOdooId,
                          Map<Long, Integer> productoIdOdooPorProductoLocal) {
        Map<String, Object> values = new HashMap<>();
        values.put("partner_id", partnerOdooId);
        if (userOdooId != null) {
            values.put("user_id", userOdooId);
        }
        if (pedido.getFecha() != null) {
            values.put("date_order", pedido.getFecha().format(ODOO_DATETIME));
        }
        // El campo `note` de sale.order se renderiza después de las líneas en
        // el PDF del pedido. Solo lo enviamos si hay texto: si no, dejamos que
        // Odoo aplique su valor por defecto (vacío) y evitamos pisar notas
        // configuradas en la plantilla del partner.
        if (pedido.getObservaciones() != null && !pedido.getObservaciones().isBlank()) {
            values.put("note", pedido.getObservaciones());
        }

        List<Object> orderLines = new ArrayList<>();
        for (LineaPedido linea : pedido.getLineas()) {
            Integer productOdooId = productoIdOdooPorProductoLocal.get(linea.getProducto().getId());
            Map<String, Object> lineValues = new HashMap<>();
            lineValues.put("product_id", productOdooId);
            lineValues.put("product_uom_qty", linea.getCantidade());
            if (linea.getPrecio() != null) {
                lineValues.put("price_unit", linea.getPrecio().doubleValue());
            }
            if (linea.getDescripcion() != null) {
                lineValues.put("name", linea.getDescripcion());
            }
            // Tupla (0, 0, {valores}) = "crear una nueva línea con estos valores".
            // Es la forma estándar de Odoo para anidar one2many al crear el padre.
            orderLines.add(Arrays.asList(0, 0, lineValues));
        }
        values.put("order_line", orderLines);

        return client.create(MODEL, values);
    }

    /**
     * Lee un pedido de Odoo por su id. Se usa inmediatamente después de
     * crearlo para obtener el número ({@code name}, p. ej. "S00042") y los
     * totales definitivos calculados por Odoo con la posición fiscal aplicada.
     *
     * @param idOdoo id del {@code sale.order}
     * @return el registro, o null si no existe
     */
    public Map<String, Object> findById(int idOdoo) {
        List<Map<String, Object>> resultado = client.read(MODEL, List.of(idOdoo), FIELDS);
        return resultado.isEmpty() ? null : resultado.get(0);
    }

    /**
     * Confirma un {@code sale.order} en Odoo (pasa de {@code state='draft'} a
     * {@code 'sale'}). Sin esta llamada el pedido queda como "Presupuesto" y
     * no aparece en la vista de "Pedidos de venta" — lo cual no encaja con el
     * flujo de preventa B2B, donde el comercial cierra la venta in situ y no
     * sólo la propone.
     *
     * {@code action_confirm} es un método de instancia de {@code sale.order}
     * (no un CRUD); además del cambio de estado puede disparar las acciones
     * configuradas en Odoo (reservar/descontar stock, generar factura, etc.),
     * que son ortogonales a esta integración.
     *
     * @param idOdoo id del {@code sale.order} ya creado
     */
    public void confirmar(int idOdoo) {
        client.execute(MODEL, "action_confirm", List.of(List.of(idOdoo)));
    }

    /**
     * Obtiene los pedidos confirmados de Odoo para importar a MySQL.
     *
     * El dominio filtra por:
     * <ul>
     *   <li>{@code state in (sale, done)} — descarta presupuestos en borrador
     *       y pedidos cancelados (decisión de producto: el preventa solo ve
     *       ventas cerradas).</li>
     *   <li>{@code company_id = empresa por defecto} cuando es accesible —
     *       evita ver pedidos de otras empresas a las que el usuario de la
     *       API tenga acceso (mismo filtro que usa la importación de clientes).</li>
     * </ul>
     *
     * @return lista de registros de Odoo con todos los campos de cabecera
     */
    public List<Map<String, Object>> findPedidos() {
        Integer companyId = client.getDefaultCompanyId();
        List<Object> domain;
        if (companyId != null) {
            domain = List.of(
                    Arrays.asList("company_id", "=", companyId),
                    Arrays.asList("state", "in", List.of("sale", "done"))
            );
        } else {
            domain = List.of(
                    Arrays.asList("state", "in", List.of("sale", "done"))
            );
        }
        return client.searchRead(MODEL, domain, FIELDS_COMPLETO);
    }

    /**
     * De una lista de ids, devuelve los que todavía existen como
     * {@code sale.order} en Odoo (en cualquier estado), junto con su
     * {@code state} actual. Se usa en la reconciliación para distinguir tres
     * casos:
     * <ul>
     *   <li>id ausente del mapa → eliminado por completo en Odoo.</li>
     *   <li>id presente con {@code state='cancel'} → cancelado en Odoo, debe
     *       reflejarse como ANULADO en MySQL.</li>
     *   <li>id presente con cualquier otro estado (p. ej. {@code draft}) →
     *       no se considera borrado ni cancelado, se deja como esté.</li>
     * </ul>
     *
     * @param ids ids a comprobar
     * @return mapa id → state de los pedidos que siguen existiendo
     */
    public Map<Integer, String> findExistingStates(List<Integer> ids) {
        if (ids == null || ids.isEmpty()) {
            return Map.of();
        }
        List<Object> domain = List.of(Arrays.asList("id", "in", ids));
        List<Map<String, Object>> rows = client.searchRead(MODEL, domain, List.of("id", "state"));
        Map<Integer, String> resultado = new HashMap<>();
        for (Map<String, Object> row : rows) {
            resultado.put(((Number) row.get("id")).intValue(), (String) row.get("state"));
        }
        return resultado;
    }

    /**
     * Lee las líneas ({@code sale.order.line}) de un conjunto de pedidos en
     * una sola llamada XML-RPC. Se hace así (read en bloque) en lugar de una
     * llamada por pedido para evitar el clásico problema N+1 — la importación
     * suele traer decenas de pedidos a la vez.
     *
     * @param idsLinea ids de {@code sale.order.line} a leer
     * @return lista de registros de Odoo
     */
    public List<Map<String, Object>> findOrderLines(List<Integer> idsLinea) {
        if (idsLinea == null || idsLinea.isEmpty()) {
            return List.of();
        }
        return client.read(MODEL_LINEA, idsLinea, FIELDS_LINEA);
    }
}
