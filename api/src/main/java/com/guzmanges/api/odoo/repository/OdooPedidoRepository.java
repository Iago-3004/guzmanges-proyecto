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

    /**
     * Campos que se leen del {@code sale.order} tras crearlo: número asignado
     * por Odoo y totales ya recalculados con la posición fiscal del cliente.
     */
    private static final List<String> FIELDS = List.of(
            "id", "name", "amount_untaxed", "amount_tax", "amount_total");

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
}
