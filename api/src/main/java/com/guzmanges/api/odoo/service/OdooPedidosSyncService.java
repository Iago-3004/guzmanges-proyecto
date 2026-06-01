package com.guzmanges.api.odoo.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.guzmanges.api.entity.Cliente;
import com.guzmanges.api.entity.EstadoPedido;
import com.guzmanges.api.entity.EstadoSync;
import com.guzmanges.api.entity.LineaPedido;
import com.guzmanges.api.entity.Pedido;
import com.guzmanges.api.entity.Produto;
import com.guzmanges.api.entity.TipoUsuario;
import com.guzmanges.api.entity.Usuario;
import com.guzmanges.api.odoo.mapper.OdooPedidoMapper;
import com.guzmanges.api.odoo.repository.OdooClienteRepository;
import com.guzmanges.api.odoo.repository.OdooPedidoRepository;
import com.guzmanges.api.repository.ClienteRepository;
import com.guzmanges.api.repository.PedidoRepository;
import com.guzmanges.api.repository.ProdutoRepository;
import com.guzmanges.api.repository.UsuarioRepository;

/**
 * Servicio de envío de pedidos a Odoo (cierre del ciclo bidireccional).
 *
 * Para cada pedido en estado {@code PENDENTE}:
 * <ol>
 *     <li>Resuelve el {@code partner_id} (cliente) y el {@code user_id}
 *         (comercial) en Odoo. Si el cliente todavía no se sincronizó, el
 *         pedido queda en ERRO con un mensaje específico — la app lo
 *         detecta y lo reintenta tras subir primero el cliente.</li>
 *     <li>Resuelve el {@code product_id} de cada línea. Si algún producto
 *         no tiene idOdoo (caso teórico: se borró del catálogo entre el
 *         alta del pedido y su envío), el pedido queda en ERRO.</li>
 *     <li>Crea el {@code sale.order} en Odoo y lo vuelve a leer para
 *         obtener el {@code name} (número definitivo) y los totales
 *         recalculados aplicando la posición fiscal del cliente.</li>
 *     <li>Sobrescribe los totales locales con los definitivos y pasa el
 *         pedido a {@code CONFIRMADO + SINCRONIZADO}. La app, en su
 *         siguiente sincronización descendente, baja los totales nuevos.</li>
 * </ol>
 *
 * El desglose entre IVA y recargo de equivalencia se mantiene calculado en
 * local (no se separa al leer de Odoo): {@code amount_tax} agrega ambos,
 * pero la previsualización del backend ya conoce ambas magnitudes a partir
 * de las líneas. Se documenta como mejora opcional en la memoria.
 */
@Service
public class OdooPedidosSyncService {

    private static final Logger log = LoggerFactory.getLogger(OdooPedidosSyncService.class);

    private final PedidoRepository pedidoRepository;
    private final ClienteRepository clienteRepository;
    private final ProdutoRepository produtoRepository;
    private final UsuarioRepository usuarioRepository;
    private final OdooPedidoRepository odooPedidoRepository;
    private final OdooClienteRepository odooClienteRepository;
    private final OdooPedidoMapper odooPedidoMapper;

    /**
     * Palabra clave (compartida con {@link com.guzmanges.api.mapper.ClienteMapper}
     * y {@link com.guzmanges.api.service.PedidoService}) que identifica el
     * régimen de recargo de equivalencia en el nombre de la posición fiscal
     * del cliente. Si la posición fiscal no la contiene, el cliente no aplica
     * RE y al releer de Odoo dejamos {@code totalRE = 0} sin restar nada del
     * {@code amount_tax}.
     */
    private final String recargoKeyword;

    public OdooPedidosSyncService(PedidoRepository pedidoRepository,
                                  ClienteRepository clienteRepository,
                                  ProdutoRepository produtoRepository,
                                  UsuarioRepository usuarioRepository,
                                  OdooPedidoRepository odooPedidoRepository,
                                  OdooClienteRepository odooClienteRepository,
                                  OdooPedidoMapper odooPedidoMapper,
                                  @Value("${app.posicion-fiscal.recargo-keyword:recargo}") String recargoKeyword) {
        this.pedidoRepository = pedidoRepository;
        this.clienteRepository = clienteRepository;
        this.produtoRepository = produtoRepository;
        this.usuarioRepository = usuarioRepository;
        this.odooPedidoRepository = odooPedidoRepository;
        this.odooClienteRepository = odooClienteRepository;
        this.odooPedidoMapper = odooPedidoMapper;
        this.recargoKeyword = recargoKeyword.toLowerCase();
    }

    /**
     * Importa a la BD local los pedidos confirmados de Odoo. Para cada
     * registro de Odoo se busca el equivalente en MySQL por idOdoo: si ya
     * existe y {@code write_date} es posterior al último guardado, se
     * actualiza; si es nuevo, se crea; si está al día, se omite.
     *
     * <p>Los pedidos saltados (cliente no sincronizado todavía, líneas sin
     * producto resoluble) se registran en el log pero no detienen la
     * importación.
     *
     * <p>Al terminar, los pedidos locales con idOdoo que ya no aparecen en
     * Odoo se borran (reconciliación), igual que se hace con clientes.
     *
     * @return número de pedidos creados o actualizados
     */
    @Transactional
    public int importarPedidosDesdeOdoo() {
        log.info("=== IMPORTANDO PEDIDOS DESDE ODOO ===");
        List<Map<String, Object>> pedidosOdoo = odooPedidoRepository.findPedidos();
        log.info("Pedidos encontrados en Odoo: {}", pedidosOdoo.size());

        // Lectura masiva de las líneas de todos los pedidos en una sola
        // llamada XML-RPC, para no caer en N+1.
        Map<Integer, Map<String, Object>> lineasPorId = cargarLineas(pedidosOdoo);

        // Caches por importación, evitan ir a la BD por cada pedido.
        Map<Integer, Usuario> cacheUsuario = new HashMap<>();
        Usuario usuarioFallback = usuarioRepository
                .findFirstByTipoUsuario(TipoUsuario.ADMIN)
                .orElse(null);

        int nuevos = 0;
        int actualizados = 0;
        int sinCambios = 0;
        int saltados = 0;
        Set<String> idsVistos = new HashSet<>();
        for (Map<String, Object> datosOdoo : pedidosOdoo) {
            try {
                String idOdoo = String.valueOf(((Number) datosOdoo.get("id")).intValue());
                idsVistos.add(idOdoo);

                Pedido desdeOdoo = odooPedidoMapper.fromOdooToPedido(
                        datosOdoo,
                        lineasPorId,
                        idOdooCliente -> clienteRepository
                                .findByIdOdoo(idOdooCliente).orElse(null),
                        idOdooProducto -> produtoRepository
                                .findByIdOdoo(idOdooProducto).orElse(null),
                        odooUserId -> resolverUsuario(odooUserId, cacheUsuario),
                        usuarioFallback);
                if (desdeOdoo == null) {
                    saltados++;
                    log.info("[ODOO -> DB] Saltado pedido idOdoo={} (cliente o productos no encontrados en local)",
                            idOdoo);
                    continue;
                }

                Optional<Pedido> existente = pedidoRepository.findByIdOdoo(idOdoo);
                if (existente.isPresent()) {
                    Pedido pedido = existente.get();
                    if (pedido.getFechaModificacionOdoo() != null
                            && desdeOdoo.getFechaModificacionOdoo() != null
                            && !desdeOdoo.getFechaModificacionOdoo()
                                    .isAfter(pedido.getFechaModificacionOdoo())) {
                        sinCambios++;
                        continue;
                    }
                    odooPedidoMapper.copiarDatosDeOdoo(pedido, desdeOdoo);
                    // Las líneas se reemplazan en bloque: clear+addAll dispara
                    // orphanRemoval sobre las anteriores y persiste las nuevas
                    // con el pedido como dueño.
                    pedido.getLineas().clear();
                    for (LineaPedido nueva : desdeOdoo.getLineas()) {
                        nueva.setPedido(pedido);
                        pedido.getLineas().add(nueva);
                    }
                    pedidoRepository.save(pedido);
                    actualizados++;
                } else {
                    // El mapper construye las líneas apuntando al pedido nuevo
                    // (setPedido); JPA persiste todo por cascada.
                    pedidoRepository.save(desdeOdoo);
                    nuevos++;
                    log.info("[ODOO -> DB] Nuevo pedido: {} (idOdoo: {})",
                            desdeOdoo.getNumero(), idOdoo);
                }
            } catch (Exception e) {
                log.error("[ODOO -> DB] Error importando pedido idOdoo={}: {}",
                        datosOdoo.get("id"), e.getMessage());
            }
        }

        log.info("=== PEDIDOS: {} nuevos, {} actualizados, {} sin cambios, {} saltados (de {} en Odoo) ===",
                nuevos, actualizados, sinCambios, saltados, pedidosOdoo.size());

        reconciliarPedidosBorrados(idsVistos);
        return nuevos + actualizados;
    }

    /**
     * Recoge todos los ids de {@code sale.order.line} de los pedidos a
     * importar y los lee de Odoo en una sola llamada. Devuelve un índice
     * id-de-línea → registro completo, listo para que el mapper resuelva las
     * líneas de cada pedido sin más viajes a Odoo.
     */
    private Map<Integer, Map<String, Object>> cargarLineas(
            List<Map<String, Object>> pedidosOdoo) {
        List<Integer> idsLinea = new ArrayList<>();
        for (Map<String, Object> pedido : pedidosOdoo) {
            Object raw = pedido.get("order_line");
            if (raw instanceof Object[] arr) {
                for (Object id : arr) {
                    if (id instanceof Number n) idsLinea.add(n.intValue());
                }
            }
        }
        if (idsLinea.isEmpty()) return Map.of();

        List<Map<String, Object>> lineasOdoo = odooPedidoRepository.findOrderLines(idsLinea);
        Map<Integer, Map<String, Object>> indice = new HashMap<>(lineasOdoo.size());
        for (Map<String, Object> linea : lineasOdoo) {
            Object idObj = linea.get("id");
            if (idObj instanceof Number n) indice.put(n.intValue(), linea);
        }
        return indice;
    }

    /**
     * Detecta los pedidos que han dejado de estar "vivos" en Odoo y los marca
     * como {@code ANULADO} en MySQL bumpando {@code fechaModificacion}. Mismo
     * patrón que la reconciliación de clientes: no hacemos borrado físico
     * para que la sincronización incremental de la app pueda devolver la fila
     * con el nuevo estado; si la elimináramos, la app no se enteraría y el
     * pedido quedaría visible en el móvil indefinidamente. La app, al recibir
     * un pedido en estado {@code ANULADO}, lo elimina de su BD local.
     *
     * Dos casos disparan la anulación:
     * <ul>
     *   <li>El pedido ya no existe en Odoo (eliminado físicamente).</li>
     *   <li>Existe pero con {@code state='cancel'} (cancelado en Odoo).</li>
     * </ul>
     * En ambos casos el comercial ya no debe verlo en la app.
     *
     * Los pedidos que siguen existiendo con otro estado distinto al confirmado
     * (p. ej. {@code draft}) se dejan intactos: es un caso raro (un pedido
     * confirmado vuelto a borrador) y la decisión correcta no es obvia, así
     * que de momento no se toca.
     */
    private void reconciliarPedidosBorrados(Set<String> idsVistos) {
        List<Pedido> candidatos = pedidoRepository.findByIdOdooIsNotNull().stream()
                .filter(p -> !idsVistos.contains(p.getIdOdoo()))
                .toList();
        if (candidatos.isEmpty()) {
            return;
        }
        List<Integer> idsCandidatos = candidatos.stream()
                .map(p -> Integer.parseInt(p.getIdOdoo()))
                .toList();
        Map<Integer, String> estadosEnOdoo = odooPedidoRepository.findExistingStates(idsCandidatos);

        // Anulamos los que ya no existen en Odoo o existen con state='cancel'.
        // Filtramos también los que ya estaban ANULADO en MySQL: rebumpar la
        // fecha solo añade ruido a la siguiente sincronización incremental.
        List<Pedido> aAnular = candidatos.stream()
                .filter(p -> {
                    String estadoOdoo = estadosEnOdoo.get(Integer.parseInt(p.getIdOdoo()));
                    return estadoOdoo == null || "cancel".equals(estadoOdoo);
                })
                .filter(p -> p.getEstadoPedido() != EstadoPedido.ANULADO)
                .toList();

        LocalDateTime ahora = LocalDateTime.now();
        for (Pedido pedido : aAnular) {
            pedido.setEstadoPedido(EstadoPedido.ANULADO);
            pedido.setFechaModificacion(ahora);
            pedidoRepository.save(pedido);
            String motivo = estadosEnOdoo.containsKey(Integer.parseInt(pedido.getIdOdoo()))
                    ? "cancelado en Odoo"
                    : "borrado en Odoo";
            log.info("[ODOO -> DB] Pedido {} (idOdoo {}) {}: anulado en MySQL",
                    pedido.getNumero(), pedido.getIdOdoo(), motivo);
        }
        if (!aAnular.isEmpty()) {
            log.info("=== RECONCILIACIÓN DE PEDIDOS: {} anulados ===", aAnular.size());
        }
    }

    /**
     * Resuelve el {@link Usuario} local a partir del id del vendedor en Odoo:
     * obtiene su login/email en Odoo y busca el usuario por ese email. Usa
     * una caché por importación. Devuelve null si no hay equivalente local
     * (el caller aplicará el fallback de ADMIN).
     */
    private Usuario resolverUsuario(Integer odooUserId, Map<Integer, Usuario> cache) {
        if (odooUserId == null) return null;
        if (cache.containsKey(odooUserId)) return cache.get(odooUserId);
        Usuario encontrado = null;
        String[] identidades = odooClienteRepository.findUserLoginAndEmail(odooUserId);
        if (identidades != null) {
            for (String identidad : identidades) {
                if (identidad != null) {
                    encontrado = usuarioRepository.findByEmailIgnoreCase(identidad).orElse(null);
                    if (encontrado != null) break;
                }
            }
        }
        cache.put(odooUserId, encontrado);
        return encontrado;
    }

    /**
     * Recorre los pedidos pendientes de envío y los sube a Odoo de uno en uno.
     * Cada error se aísla en su propio pedido (se marca ERRO con motivo) y la
     * iteración continúa con el siguiente.
     *
     * @return resumen del envío (éxitos y errores, con prefijo "Pedido")
     */
    @Transactional
    public SyncResult enviarPedidosPendientes() {
        SyncResult result = new SyncResult();
        // Se incluyen los pedidos en ERRO: sus fallos típicos son transitorios
        // (cliente sin sincronizar todavía, Odoo caído, bug puntual ya corregido)
        // y se recuperan solos al siguiente tic. Si el error es permanente, el
        // pedido seguirá fallando y se reflejará en la app como ERRO, pero sin
        // bloquear el envío del resto.
        List<Pedido> pendientes = pedidoRepository
                .findByEstadoSyncIn(Set.of(EstadoSync.PENDENTE, EstadoSync.ERRO))
                .stream()
                .filter(p -> p.getEstadoPedido() == EstadoPedido.BORRADOR)
                .toList();
        if (pendientes.isEmpty()) {
            log.info("[DB -> ODOO] No hay pedidos pendientes de enviar");
            return result;
        }

        log.info("=== ENVIANDO {} PEDIDOS PENDIENTES A ODOO (incluyendo reintentos) ===", pendientes.size());
        // Cache de comerciales: el mismo preventa suele tener varios pedidos en
        // la misma tanda; sin cache, cada pedido haría una búsqueda por email
        // en res.users.
        Map<String, Integer> cacheVendedores = new HashMap<>();

        for (Pedido pedido : pendientes) {
            try {
                enviarPedido(pedido, cacheVendedores);
                result.addExito();
            } catch (PedidoPendienteException e) {
                marcarError(pedido, e.getMessage());
                result.addError("Pedido", pedido.getId(), e.getMessage());
                log.info("[DB -> ODOO] Pedido {} en espera: {}", pedido.getId(), e.getMessage());
            } catch (Exception e) {
                marcarError(pedido, e.getMessage());
                result.addError("Pedido", pedido.getId(), e.getMessage());
                log.error("[DB -> ODOO] Error enviando pedido {}: {}", pedido.getId(), e.getMessage());
            }
        }

        log.info("=== ENVÍO DE PEDIDOS A ODOO FINALIZADO: {} ===", result);
        return result;
    }

    /**
     * Envía un único pedido a Odoo de forma inmediata. Pensado para llamarse
     * justo después de guardar un pedido nuevo desde {@code POST /pedidos},
     * para que el usuario vea los totales definitivos en la respuesta sin
     * esperar al scheduler periódico.
     *
     * Si Odoo está caído o el envío falla (p. ej. el cliente todavía no se
     * sincronizó), se lanza la excepción al llamador, que debe tratarla:
     * típicamente, dejar el pedido en PENDENTE y delegar el reintento al
     * scheduler. Nada se marca como ERRO desde aquí (a diferencia del bucle
     * {@link #enviarPedidosPendientes()}), porque el primer intento inmediato
     * no debe gastar el "cupo" de error si la causa es transitoria.
     *
     * Comparte transacción con el llamador: si se invoca desde dentro de
     * {@code @Transactional}, los cambios sobre la entidad ({@code idOdoo},
     * número, totales) se persisten en el mismo commit.
     */
    public void enviarUno(Pedido pedido) {
        enviarPedido(pedido, new HashMap<>());
    }

    /**
     * Envía un único pedido a Odoo y actualiza la entidad local con los
     * datos definitivos (número e importes recalculados con posición fiscal).
     */
    private void enviarPedido(Pedido pedido, Map<String, Integer> cacheVendedores) {
        Cliente cliente = pedido.getCliente();
        Integer partnerOdooId = resolverPartnerId(cliente);

        Usuario usuario = pedido.getUsuario();
        Integer userOdooId = resolverVendedorId(usuario, cacheVendedores);

        Map<Long, Integer> productoOdooPorLocal = resolverProductosOdoo(pedido.getLineas());

        Integer idOdoo = odooPedidoRepository.create(pedido, partnerOdooId, userOdooId, productoOdooPorLocal);
        log.info("[DB -> ODOO] Pedido {} creado en Odoo, idOdoo={}", pedido.getId(), idOdoo);

        // Sin confirmar, el sale.order se queda como "Presupuesto" (state=draft)
        // y no aparece en la vista de Pedidos de Venta de Odoo. Se confirma
        // siempre para que el flujo de preventa B2B encaje: el pedido capturado
        // por el comercial es un pedido real, no una propuesta.
        odooPedidoRepository.confirmar(idOdoo);
        log.info("[DB -> ODOO] Pedido {} confirmado en Odoo", pedido.getId());

        Map<String, Object> respuesta = odooPedidoRepository.findById(idOdoo);
        if (respuesta == null) {
            throw new IllegalStateException("Odoo aceptó el sale.order pero no se puede releer (id=" + idOdoo + ")");
        }
        aplicarRespuestaOdoo(pedido, idOdoo, respuesta);
        pedidoRepository.save(pedido);
    }

    /**
     * Resuelve el {@code partner_id} a partir del idOdoo del cliente. Si el
     * cliente todavía no tiene idOdoo (alta local todavía no enviada) se
     * lanza {@link PedidoPendienteException}: la app trata este caso como
     * "esperando a que se sincronice el cliente" y lo reintenta automáticamente
     * en la siguiente vuelta, una vez se haya subido el cliente.
     */
    private Integer resolverPartnerId(Cliente cliente) {
        if (cliente.getIdOdoo() == null || cliente.getIdOdoo().isBlank()) {
            throw new PedidoPendienteException(
                    "El cliente '" + cliente.getRazonSocial() + "' todavía no está sincronizado con Odoo");
        }
        try {
            return Integer.parseInt(cliente.getIdOdoo());
        } catch (NumberFormatException e) {
            throw new IllegalStateException("idOdoo del cliente no es numérico: " + cliente.getIdOdoo());
        }
    }

    /**
     * Resuelve el {@code user_id} en Odoo a partir del email del usuario local.
     * Si el usuario no tiene email o ese email no existe en Odoo, devuelve null
     * (el pedido se enviará sin vendedor — Odoo asignará el de la API).
     */
    private Integer resolverVendedorId(Usuario usuario, Map<String, Integer> cache) {
        if (usuario == null || usuario.getEmail() == null || usuario.getEmail().isBlank()) {
            return null;
        }
        String email = usuario.getEmail();
        if (cache.containsKey(email)) {
            return cache.get(email);
        }
        Integer userId = odooClienteRepository.findUserIdByEmail(email);
        if (userId == null) {
            log.info("[DB -> ODOO] Sin vendedor en Odoo para el email {} (usuario {})",
                    email, usuario.getNombreUsuario());
        }
        cache.put(email, userId);
        return userId;
    }

    /**
     * Construye el mapa {idProductoLocal → idOdoo} para todas las líneas del
     * pedido. Si algún producto no tiene idOdoo (caso teórico: se borró del
     * catálogo después de crear el pedido), lanza error.
     */
    private Map<Long, Integer> resolverProductosOdoo(List<LineaPedido> lineas) {
        Map<Long, Integer> mapa = new HashMap<>();
        for (LineaPedido linea : lineas) {
            Produto producto = linea.getProducto();
            if (producto.getIdOdoo() == null || producto.getIdOdoo().isBlank()) {
                throw new IllegalStateException(
                        "El producto '" + producto.getDescripcion() + "' no está sincronizado con Odoo");
            }
            try {
                mapa.put(producto.getId(), Integer.parseInt(producto.getIdOdoo()));
            } catch (NumberFormatException e) {
                throw new IllegalStateException("idOdoo del producto no es numérico: " + producto.getIdOdoo());
            }
        }
        return mapa;
    }

    /**
     * Copia en el pedido local el id, número y totales definitivos devueltos
     * por Odoo, y lo marca como confirmado y sincronizado.
     *
     * Odoo agrega IVA y recargo de equivalencia en {@code amount_tax} sin
     * separarlos: la separación se decide aquí en función de la posición
     * fiscal del cliente, que es la fuente de verdad sobre si aplica RE.
     *
     * <ul>
     *   <li>Cliente con posición fiscal de recargo de equivalencia: se
     *       mantiene el {@code totalRE} provisional (calculado en
     *       {@link com.guzmanges.api.service.PedidoService} con la tabla
     *       legal española 21→5.2 / 10→1.4 / 4→0.5) y se le resta al
     *       {@code amount_tax} para reconstruir el IVA puro.</li>
     *   <li>Cliente con cualquier otra posición fiscal (intracomunitario,
     *       exento, normal sin RE...): {@code totalRE = 0}. Si el preventa
     *       envió un RE explícito en alguna línea, Odoo ya lo ignoró al
     *       aplicar la posición fiscal correspondiente, así que aquí
     *       descartamos el RE provisional para que el desglose refleje la
     *       realidad de Odoo y no muestre un RE falso al preventa.</li>
     * </ul>
     *
     * En ambos casos se preserva el invariante {@code total = base + iva + re}.
     */
    private void aplicarRespuestaOdoo(Pedido pedido, Integer idOdoo, Map<String, Object> respuesta) {
        pedido.setIdOdoo(String.valueOf(idOdoo));

        Object nombre = respuesta.get("name");
        if (nombre instanceof String s && !"false".equals(s)) {
            pedido.setNumero(s);
        }

        BigDecimal amountUntaxed = leerImporte(respuesta, "amount_untaxed");
        BigDecimal amountTax = leerImporte(respuesta, "amount_tax");
        BigDecimal amountTotal = leerImporte(respuesta, "amount_total");

        pedido.setTotalBase(amountUntaxed.setScale(2, RoundingMode.HALF_UP));

        if (clienteAplicaRecargoEquivalencia(pedido.getCliente())) {
            BigDecimal totalReProvisional = pedido.getTotalRE() != null
                    ? pedido.getTotalRE() : BigDecimal.ZERO;
            BigDecimal ivaPuro = amountTax.subtract(totalReProvisional);
            // Fallback: si el preventa envió un RE mayor del que Odoo realmente
            // aplica para este cliente, ivaPuro queda negativo. En ese caso
            // colapsamos a "IVA contiene todos los impuestos" y RE=0.
            if (ivaPuro.signum() >= 0) {
                pedido.setTotalIva(ivaPuro.setScale(2, RoundingMode.HALF_UP));
            } else {
                pedido.setTotalIva(amountTax.setScale(2, RoundingMode.HALF_UP));
                pedido.setTotalRE(BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP));
            }
        } else {
            pedido.setTotalIva(amountTax.setScale(2, RoundingMode.HALF_UP));
            pedido.setTotalRE(BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP));
        }

        pedido.setTotal(amountTotal.setScale(2, RoundingMode.HALF_UP));

        pedido.setEstadoPedido(EstadoPedido.CONFIRMADO);
        pedido.setEstadoSync(EstadoSync.SINCRONIZADO);
        pedido.setFechaModificacion(LocalDateTime.now());
    }

    /**
     * Indica si la posición fiscal del cliente identifica el régimen de
     * recargo de equivalencia (misma lógica que {@link
     * com.guzmanges.api.mapper.ClienteMapper} y {@link
     * com.guzmanges.api.service.PedidoService}).
     */
    private boolean clienteAplicaRecargoEquivalencia(Cliente cliente) {
        return cliente.getPosicionFiscal() != null
                && cliente.getPosicionFiscal().toLowerCase().contains(recargoKeyword);
    }

    /**
     * Lee un campo numérico de la respuesta de Odoo. Odoo puede devolver
     * Integer, Double o Float según el tipo; se normaliza siempre a BigDecimal.
     * Si el campo no está o es "false", devuelve cero.
     */
    private BigDecimal leerImporte(Map<String, Object> datos, String campo) {
        Object valor = datos.get(campo);
        if (valor instanceof Number n) {
            return BigDecimal.valueOf(n.doubleValue());
        }
        return BigDecimal.ZERO;
    }

    private void marcarError(Pedido pedido, String motivo) {
        pedido.setEstadoSync(EstadoSync.ERRO);
        pedido.setFechaModificacion(LocalDateTime.now());
        pedidoRepository.save(pedido);
    }

    /**
     * Excepción interna para distinguir "el pedido aún no se puede enviar"
     * (ej. el cliente todavía no se sincronizó) de un error real. Se usa solo
     * para tipar el log: el resultado en BD es el mismo (estado ERRO con motivo).
     */
    private static class PedidoPendienteException extends RuntimeException {
        PedidoPendienteException(String mensaje) {
            super(mensaje);
        }
    }
}
