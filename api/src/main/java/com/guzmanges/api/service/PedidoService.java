package com.guzmanges.api.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.guzmanges.api.odoo.service.OdooPedidosSyncService;

import com.guzmanges.api.dto.CrearLineaRequest;
import com.guzmanges.api.dto.CrearPedidoRequest;
import com.guzmanges.api.dto.PedidoResponse;
import com.guzmanges.api.entity.Cliente;
import com.guzmanges.api.entity.EstadoPedido;
import com.guzmanges.api.entity.EstadoSync;
import com.guzmanges.api.entity.LineaPedido;
import com.guzmanges.api.entity.Pedido;
import com.guzmanges.api.entity.Produto;
import com.guzmanges.api.entity.TipoUsuario;
import com.guzmanges.api.entity.Usuario;
import com.guzmanges.api.exception.ResourceNotFoundException;
import com.guzmanges.api.mapper.PedidoMapper;
import com.guzmanges.api.repository.ClienteRepository;
import com.guzmanges.api.repository.PedidoRepository;
import com.guzmanges.api.repository.ProdutoRepository;
import com.guzmanges.api.repository.UsuarioRepository;

/**
 * Lógica de negocio de los pedidos: alta desde la app y consulta por el preventa
 * autenticado.
 *
 * Visibilidad: un usuario PREVENTA solo ve sus propios pedidos; un ADMIN ve
 * todos. El filtro por usuario se aplica aquí (no en el repositorio puro)
 * porque depende de la sesión de seguridad.
 */
@Service
public class PedidoService {

    private static final Logger log = LoggerFactory.getLogger(PedidoService.class);

    private final PedidoRepository pedidoRepository;
    private final ClienteRepository clienteRepository;
    private final ProdutoRepository produtoRepository;
    private final UsuarioRepository usuarioRepository;
    private final PedidoMapper pedidoMapper;
    private final OdooPedidosSyncService odooPedidosSyncService;

    /**
     * Palabra clave (compartida con {@link com.guzmanges.api.mapper.ClienteMapper})
     * con la que se reconoce el régimen de recargo de equivalencia en el nombre
     * de la posición fiscal del cliente. Mantenerla en una sola propiedad evita
     * que el flag del DTO y el cálculo del recargo aquí discrepen.
     */
    private final String recargoKeyword;

    public PedidoService(PedidoRepository pedidoRepository,
                         ClienteRepository clienteRepository,
                         ProdutoRepository produtoRepository,
                         UsuarioRepository usuarioRepository,
                         PedidoMapper pedidoMapper,
                         OdooPedidosSyncService odooPedidosSyncService,
                         @Value("${app.posicion-fiscal.recargo-keyword:recargo}") String recargoKeyword) {
        this.pedidoRepository = pedidoRepository;
        this.clienteRepository = clienteRepository;
        this.produtoRepository = produtoRepository;
        this.usuarioRepository = usuarioRepository;
        this.pedidoMapper = pedidoMapper;
        this.odooPedidosSyncService = odooPedidosSyncService;
        this.recargoKeyword = recargoKeyword.toLowerCase();
    }

    /**
     * Lista los pedidos visibles para el usuario autenticado, descendente por
     * fecha. Un preventa solo ve los suyos; un admin los ve todos.
     */
    @Transactional(readOnly = true)
    public List<PedidoResponse> listar(Authentication authentication) {
        Usuario usuario = resolverUsuario(authentication);
        List<Pedido> pedidos = esAdmin(usuario)
                ? pedidoRepository.findAllByOrderByFechaDesc()
                : pedidoRepository.findByUsuarioOrderByFechaDesc(usuario);
        return pedidos.stream().map(pedidoMapper::toResponse).toList();
    }

    /**
     * Lista los pedidos modificados desde la fecha indicada, visibles para el
     * usuario autenticado. Pensado para sincronización incremental.
     */
    @Transactional(readOnly = true)
    public List<PedidoResponse> listarModificadosDesde(LocalDateTime modificadoDesde,
                                                       Authentication authentication) {
        Usuario usuario = resolverUsuario(authentication);
        List<Pedido> pedidos = esAdmin(usuario)
                ? pedidoRepository.findByFechaModificacionGreaterThanEqualOrderByFechaDesc(modificadoDesde)
                : pedidoRepository.findByFechaModificacionGreaterThanEqualAndUsuarioOrderByFechaDesc(
                        modificadoDesde, usuario);
        return pedidos.stream().map(pedidoMapper::toResponse).toList();
    }

    /**
     * Obtiene un pedido por su identificador, comprobando antes que pertenezca
     * al preventa autenticado (o que el autenticado sea admin).
     *
     * @throws ResourceNotFoundException si no existe o si no es propiedad del
     *                                   usuario autenticado (no se distingue
     *                                   entre los dos casos para no filtrar
     *                                   información sobre pedidos ajenos)
     */
    @Transactional(readOnly = true)
    public PedidoResponse obtenerPorId(Long id, Authentication authentication) {
        Usuario usuario = resolverUsuario(authentication);
        Pedido pedido = pedidoRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Pedido no encontrado: " + id));
        if (!esAdmin(usuario) && !pedido.getUsuario().getId().equals(usuario.getId())) {
            throw new ResourceNotFoundException("Pedido no encontrado: " + id);
        }
        return pedidoMapper.toResponse(pedido);
    }

    /**
     * Da de alta un pedido nuevo desde la app. Se calculan los totales
     * provisionales (precio × IVA × recargo) a partir de las líneas, y a
     * continuación se intenta enviar inmediatamente a Odoo en la misma
     * petición: si Odoo responde, la entidad queda ya {@code CONFIRMADO +
     * SINCRONIZADO} con su {@code idOdoo}, número y totales definitivos (que
     * reflejan la posición fiscal del cliente) y eso es lo que devuelve el
     * POST — el preventa ve los totales reales sin tener que esperar al
     * siguiente ciclo de sincronización.
     *
     * Si el envío inmediato falla (Odoo caído, cliente todavía no
     * sincronizado, etc.), el pedido se persiste igualmente en {@code
     * BORRADOR + PENDENTE} con sus totales provisionales: el scheduler
     * periódico lo reintentará después y la app, en su próxima
     * sincronización descendente, recibirá los totales definitivos.
     *
     * Para cada línea: si la app no envía precio, IVA o recargo, se toman
     * del producto y de la posición fiscal del cliente.
     */
    @Transactional
    public PedidoResponse crear(CrearPedidoRequest request, Authentication authentication) {
        Usuario usuario = resolverUsuario(authentication);
        Cliente cliente = clienteRepository.findById(request.clienteId())
                .orElseThrow(() -> new ResourceNotFoundException(
                        "Cliente no encontrado: " + request.clienteId()));

        Pedido pedido = new Pedido();
        pedido.setCliente(cliente);
        pedido.setUsuario(usuario);
        pedido.setFecha(LocalDateTime.now());
        pedido.setEstadoPedido(EstadoPedido.BORRADOR);
        pedido.setEstadoSync(EstadoSync.PENDENTE);
        pedido.setObservaciones(normalizarObservaciones(request.observaciones()));
        pedido.setFechaModificacion(LocalDateTime.now());

        BigDecimal totalBase = BigDecimal.ZERO;
        BigDecimal totalIva = BigDecimal.ZERO;
        BigDecimal totalRE = BigDecimal.ZERO;

        for (CrearLineaRequest lineaReq : request.lineas()) {
            Produto producto = produtoRepository.findById(lineaReq.productoId())
                    .orElseThrow(() -> new ResourceNotFoundException(
                            "Producto no encontrado: " + lineaReq.productoId()));

            BigDecimal precio = lineaReq.precio() != null
                    ? lineaReq.precio()
                    : ceroSiNull(producto.getPrecioVenta());
            BigDecimal iva = lineaReq.iva() != null
                    ? lineaReq.iva()
                    : ceroSiNull(producto.getIva());
            BigDecimal recargo = lineaReq.recargoEquivalencia() != null
                    ? lineaReq.recargoEquivalencia()
                    : recargoSegunCliente(cliente, iva);
            int cantidade = lineaReq.cantidade();

            BigDecimal base = precio.multiply(BigDecimal.valueOf(cantidade));
            BigDecimal importeIva = base.multiply(iva).divide(BigDecimal.valueOf(100), 4, RoundingMode.HALF_UP);
            BigDecimal importeRE = base.multiply(recargo).divide(BigDecimal.valueOf(100), 4, RoundingMode.HALF_UP);
            BigDecimal subtotal = base.add(importeIva).add(importeRE)
                    .setScale(2, RoundingMode.HALF_UP);

            LineaPedido linea = new LineaPedido();
            linea.setPedido(pedido);
            linea.setProducto(producto);
            linea.setCodigoProducto(producto.getReferencia());
            linea.setDescripcion(producto.getDescripcion());
            linea.setPrecio(precio.setScale(2, RoundingMode.HALF_UP));
            linea.setIva(iva.setScale(2, RoundingMode.HALF_UP));
            linea.setRecargoEquivalencia(recargo.setScale(2, RoundingMode.HALF_UP));
            linea.setCantidade(cantidade);
            linea.setSubtotal(subtotal);
            pedido.getLineas().add(linea);

            totalBase = totalBase.add(base);
            totalIva = totalIva.add(importeIva);
            totalRE = totalRE.add(importeRE);
        }

        pedido.setTotalBase(totalBase.setScale(2, RoundingMode.HALF_UP));
        pedido.setTotalIva(totalIva.setScale(2, RoundingMode.HALF_UP));
        pedido.setTotalRE(totalRE.setScale(2, RoundingMode.HALF_UP));
        pedido.setTotal(totalBase.add(totalIva).add(totalRE).setScale(2, RoundingMode.HALF_UP));

        Pedido guardado = pedidoRepository.save(pedido);
        intentarEnvioInmediato(guardado);
        return pedidoMapper.toResponse(guardado);
    }

    /**
     * Intenta enviar el pedido recién guardado a Odoo en la misma transacción
     * del POST. Si Odoo responde, la entidad pasa a CONFIRMADO + SINCRONIZADO
     * con sus totales definitivos y el commit los persiste atomicamente con
     * el alta. Si Odoo falla (caído, cliente sin sincronizar, timeout...),
     * captura la excepción para NO tirar atrás el alta: el pedido queda
     * persistido como PENDENTE y el scheduler periódico lo reintentará.
     */
    private void intentarEnvioInmediato(Pedido pedido) {
        try {
            odooPedidosSyncService.enviarUno(pedido);
        } catch (Exception e) {
            log.warn("[POST /pedidos] Pedido {} guardado pero envío inmediato a Odoo falló "
                    + "— queda PENDENTE para el scheduler: {}", pedido.getId(), e.getMessage());
        }
    }

    // --- Helpers ---

    /**
     * Resuelve el {@link Usuario} a partir del nombre de usuario del JWT.
     */
    private Usuario resolverUsuario(Authentication authentication) {
        return usuarioRepository.findByNombreUsuario(authentication.getName())
                .orElseThrow(() -> new ResourceNotFoundException(
                        "Usuario no encontrado: " + authentication.getName()));
    }

    private boolean esAdmin(Usuario usuario) {
        return usuario.getTipoUsuario() == TipoUsuario.ADMIN;
    }

    private BigDecimal ceroSiNull(BigDecimal valor) {
        return valor != null ? valor : BigDecimal.ZERO;
    }

    /**
     * Limpia las observaciones recibidas: elimina espacios alrededor y devuelve
     * null si la cadena queda vacía, para que en BD no quede una cadena en
     * blanco que luego se enviaría como tal a Odoo.
     */
    private String normalizarObservaciones(String valor) {
        if (valor == null) return null;
        String limpio = valor.trim();
        return limpio.isEmpty() ? null : limpio;
    }

    /**
     * Si el cliente está sujeto al régimen de recargo de equivalencia, devuelve
     * el tipo de RE correspondiente al IVA según las tablas legales españolas:
     * 21 % → 5.2 %, 10 % → 1.4 %, 4 % → 0.5 %. En el resto de casos devuelve 0.
     *
     * Esta tabla se mantiene también en la app ({@code core/impuestos/calculadora_re.dart})
     * para que la previsualización en el móvil y el cálculo del backend coincidan.
     */
    private BigDecimal recargoSegunCliente(Cliente cliente, BigDecimal iva) {
        if (cliente.getPosicionFiscal() == null
                || !cliente.getPosicionFiscal().toLowerCase().contains(recargoKeyword)) {
            return BigDecimal.ZERO;
        }
        int ivaRedondeado = iva.setScale(0, RoundingMode.HALF_UP).intValue();
        return switch (ivaRedondeado) {
            case 21 -> new BigDecimal("5.2");
            case 10 -> new BigDecimal("1.4");
            case 4 -> new BigDecimal("0.5");
            default -> BigDecimal.ZERO;
        };
    }
}
