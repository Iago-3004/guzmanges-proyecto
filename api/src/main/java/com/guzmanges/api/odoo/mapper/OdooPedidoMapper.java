package com.guzmanges.api.odoo.mapper;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.function.Function;

import org.springframework.stereotype.Component;

import com.guzmanges.api.entity.Cliente;
import com.guzmanges.api.entity.EstadoPedido;
import com.guzmanges.api.entity.EstadoSync;
import com.guzmanges.api.entity.LineaPedido;
import com.guzmanges.api.entity.Pedido;
import com.guzmanges.api.entity.Produto;
import com.guzmanges.api.entity.Usuario;
import com.guzmanges.api.odoo.util.OdooValueUtil;

/**
 * Conversión de un {@code sale.order} de Odoo a la entidad {@link Pedido}
 * local con sus {@link LineaPedido}.
 *
 * El mapper no consulta nada por sí mismo: recibe funciones de resolución
 * (cliente, producto, usuario) que la capa de servicio cachea y pasa para
 * evitar repetir consultas a la BD durante una importación con cientos de
 * pedidos.
 */
@Component
public class OdooPedidoMapper {

    private static final DateTimeFormatter ODOO_DATETIME =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    /**
     * Convierte un registro de Odoo en un {@link Pedido} listo para guardar.
     * Si el cliente referenciado no existe en local o todas las líneas
     * tienen productos desconocidos, devuelve null para que la capa que llama
     * pueda saltarse el pedido. Como mínimo, un pedido debe tener una línea
     * resoluble.
     *
     * @param datosOdoo          campos del {@code sale.order}
     * @param lineasPorId        índice id-de-línea → registro de Odoo para
     *                           resolver las {@code order_line} sin volver a
     *                           consultarlas
     * @param resolverCliente    función que devuelve el cliente local por su
     *                           idOdoo, o null si no existe
     * @param resolverProducto   función que devuelve el producto local por su
     *                           idOdoo, o null si no existe
     * @param resolverUsuario    función que devuelve el usuario local a partir
     *                           del id de Odoo del vendedor ({@code res.users}),
     *                           o null si no tiene equivalente local
     * @param usuarioFallback    usuario a asignar cuando {@code resolverUsuario}
     *                           devuelve null (típicamente el ADMIN, para que
     *                           el campo {@code usuario_id} NOT NULL del pedido
     *                           siempre quede relleno)
     * @return el pedido listo para guardar, o null si no se puede mapear
     */
    public Pedido fromOdooToPedido(
            Map<String, Object> datosOdoo,
            Map<Integer, Map<String, Object>> lineasPorId,
            Function<String, Cliente> resolverCliente,
            Function<String, Produto> resolverProducto,
            Function<Integer, Usuario> resolverUsuario,
            Usuario usuarioFallback) {

        Integer partnerId = extraerIdReferencia(datosOdoo, "partner_id");
        if (partnerId == null) {
            return null;
        }
        Cliente cliente = resolverCliente.apply(String.valueOf(partnerId));
        if (cliente == null) {
            return null;
        }

        Integer userOdooId = extraerIdReferencia(datosOdoo, "user_id");
        Usuario usuario = userOdooId != null ? resolverUsuario.apply(userOdooId) : null;
        if (usuario == null) {
            usuario = usuarioFallback;
        }

        Pedido pedido = new Pedido();
        pedido.setIdOdoo(String.valueOf(((Number) datosOdoo.get("id")).intValue()));
        pedido.setNumero(OdooValueUtil.getStringValue(datosOdoo, "name"));
        pedido.setFecha(parsearFecha(datosOdoo.get("date_order")));
        pedido.setCliente(cliente);
        pedido.setUsuario(usuario);
        pedido.setEstadoPedido(EstadoPedido.CONFIRMADO);
        pedido.setEstadoSync(EstadoSync.SINCRONIZADO);
        pedido.setTotalBase(leerImporte(datosOdoo, "amount_untaxed"));
        // Odoo agrega IVA y RE en amount_tax: la importación inicial no
        // intenta desglosarlos (no hay cálculo provisional local del que
        // tirar). El campo totalRE queda a 0; si hace falta el desglose,
        // se inferiría leyendo los impuestos por línea — fuera de alcance.
        pedido.setTotalIva(leerImporte(datosOdoo, "amount_tax"));
        pedido.setTotalRE(BigDecimal.ZERO.setScale(2));
        pedido.setTotal(leerImporte(datosOdoo, "amount_total"));
        pedido.setFechaModificacion(LocalDateTime.now());
        pedido.setFechaModificacionOdoo(parsearFecha(datosOdoo.get("write_date")));

        List<LineaPedido> lineas = construirLineas(
                datosOdoo, lineasPorId, resolverProducto, cliente, pedido);
        if (lineas.isEmpty()) {
            return null;
        }
        pedido.setLineas(lineas);
        return pedido;
    }

    /**
     * Construye las líneas locales a partir del array {@code order_line} del
     * pedido. Las líneas con {@code display_type} (secciones y notas) o sin
     * producto resoluble se descartan, no son ventas reales.
     */
    private List<LineaPedido> construirLineas(
            Map<String, Object> datosOdoo,
            Map<Integer, Map<String, Object>> lineasPorId,
            Function<String, Produto> resolverProducto,
            Cliente cliente,
            Pedido pedido) {
        List<LineaPedido> resultado = new ArrayList<>();
        Object raw = datosOdoo.get("order_line");
        if (!(raw instanceof Object[] arr)) {
            return resultado;
        }
        for (Object idObj : arr) {
            if (!(idObj instanceof Number n)) continue;
            Map<String, Object> lineaOdoo = lineasPorId.get(n.intValue());
            if (lineaOdoo == null) continue;

            String displayType = OdooValueUtil.getStringValue(lineaOdoo, "display_type");
            if (displayType != null) continue;

            Integer productOdooId = extraerIdReferencia(lineaOdoo, "product_id");
            if (productOdooId == null) continue;
            Produto producto = resolverProducto.apply(String.valueOf(productOdooId));
            if (producto == null) continue;

            LineaPedido linea = new LineaPedido();
            linea.setPedido(pedido);
            linea.setProducto(producto);
            linea.setCodigoProducto(producto.getReferencia());
            linea.setDescripcion(textoLinea(lineaOdoo, producto));
            BigDecimal precio = leerImporte(lineaOdoo, "price_unit");
            linea.setPrecio(precio.setScale(2, RoundingMode.HALF_UP));
            linea.setIva(producto.getIva() != null
                    ? producto.getIva()
                    : BigDecimal.ZERO);
            linea.setRecargoEquivalencia(BigDecimal.ZERO.setScale(2));
            linea.setCantidade(leerEntero(lineaOdoo, "product_uom_qty"));
            // price_total ya incluye los impuestos calculados por Odoo. Si
            // no viniera, caemos en price_subtotal (sin impuestos), aceptable
            // para la previsualización.
            BigDecimal subtotal = leerImporte(lineaOdoo, "price_total");
            if (subtotal.signum() == 0) {
                subtotal = leerImporte(lineaOdoo, "price_subtotal");
            }
            linea.setSubtotal(subtotal.setScale(2, RoundingMode.HALF_UP));
            resultado.add(linea);
        }
        return resultado;
    }

    /**
     * Vuelca los campos importables de un pedido recién leído de Odoo sobre
     * uno ya existente en local. No toca el {@code idOdoo} (ya está fijado)
     * ni los UUIDs locales. Las líneas se reemplazan en bloque desde la capa
     * de servicio, no aquí.
     */
    public void copiarDatosDeOdoo(Pedido destino, Pedido desdeOdoo) {
        destino.setNumero(desdeOdoo.getNumero());
        destino.setFecha(desdeOdoo.getFecha());
        destino.setCliente(desdeOdoo.getCliente());
        destino.setUsuario(desdeOdoo.getUsuario());
        destino.setEstadoPedido(desdeOdoo.getEstadoPedido());
        destino.setEstadoSync(EstadoSync.SINCRONIZADO);
        destino.setTotalBase(desdeOdoo.getTotalBase());
        destino.setTotalIva(desdeOdoo.getTotalIva());
        destino.setTotalRE(desdeOdoo.getTotalRE());
        destino.setTotal(desdeOdoo.getTotal());
        destino.setFechaModificacion(LocalDateTime.now());
        destino.setFechaModificacionOdoo(desdeOdoo.getFechaModificacionOdoo());
    }

    /**
     * Lee el id de una relación many2one de Odoo. Las relaciones se devuelven
     * como {@code [id, "etiqueta"]} (Object[] de longitud 2) o como
     * {@code false} si no hay valor.
     */
    private Integer extraerIdReferencia(Map<String, Object> datos, String campo) {
        Object valor = datos.get(campo);
        if (valor instanceof Object[] arr && arr.length > 0 && arr[0] instanceof Number n) {
            return n.intValue();
        }
        return null;
    }

    private BigDecimal leerImporte(Map<String, Object> datos, String campo) {
        Object valor = datos.get(campo);
        if (valor instanceof Number n) {
            return BigDecimal.valueOf(n.doubleValue());
        }
        return BigDecimal.ZERO;
    }

    private Integer leerEntero(Map<String, Object> datos, String campo) {
        Object valor = datos.get(campo);
        if (valor instanceof Number n) {
            return n.intValue();
        }
        return 0;
    }

    private LocalDateTime parsearFecha(Object valor) {
        if (valor instanceof String s && !s.isBlank() && !"false".equals(s)) {
            try {
                return LocalDateTime.parse(s, ODOO_DATETIME);
            } catch (Exception ignore) {
                // formato inesperado: caemos a la marca actual
            }
        }
        return LocalDateTime.now();
    }

    /**
     * Texto descriptivo de la línea. Si Odoo trae un {@code name} no vacío,
     * se respeta (puede llevar variantes o anotaciones); si no, se usa la
     * descripción del producto local.
     */
    private String textoLinea(Map<String, Object> lineaOdoo, Produto producto) {
        String name = OdooValueUtil.getStringValue(lineaOdoo, "name");
        if (name != null && !name.isBlank()) {
            return name;
        }
        return producto.getDescripcion();
    }
}
