import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/db/dao/clientes_dao.dart';
import '../core/db/dao/pedidos_dao.dart';
import '../models/cliente.dart' show Cliente, EstadoSync;
import '../models/linea_pedido.dart';
import '../models/pedido.dart';
import '../services/pedidos_service.dart';
import '../services/sync_pedidos_service.dart';

/// Una línea aún sin pedido asignado, tal como la construye el formulario
/// antes de guardar. Es un valor de paso: el provider la convierte en
/// [LineaPedido] generando los UUIDs en el momento de persistir.
class BorradorLinea {
  final int productoId;
  final String? codigoProducto;
  final String descripcion;
  final double precio;
  final double iva;
  final double recargoEquivalencia;
  final int cantidade;

  const BorradorLinea({
    required this.productoId,
    this.codigoProducto,
    required this.descripcion,
    required this.precio,
    required this.iva,
    this.recargoEquivalencia = 0.0,
    required this.cantidade,
  });

  /// Subtotal con impuestos: `precio * cantidade * (1 + iva/100 + re/100)`.
  /// Se calcula en Dart con `num` y se redondea a 2 decimales con
  /// `toStringAsFixed`: suficiente para la previsualización (el cálculo
  /// definitivo lo recalcula el backend con `BigDecimal`).
  double get subtotal {
    final base = precio * cantidade;
    final con = base * (1 + iva / 100 + recargoEquivalencia / 100);
    return double.parse(con.toStringAsFixed(2));
  }
}

/// Estado en memoria de los pedidos.
///
/// La fuente de verdad es SQLite: el provider lee de ahí para pintar la UI y
/// llama al servidor solo cuando el [SyncProvider] orquesta la sincronización
/// descendente, o cuando el usuario crea un pedido y se intenta enviarlo en
/// la misma operación.
class PedidosProvider extends ChangeNotifier {
  final PedidosService _service;
  final PedidosDao _dao;
  final ClientesDao _clientesDao;
  final SyncPedidosService _syncService;
  final Uuid _uuid;

  PedidosProvider(
    this._service,
    this._dao,
    this._clientesDao,
    this._syncService, {
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  List<Pedido> _todos = const [];
  String _filtro = '';
  bool _soloPendientes = false;
  bool _cargando = false;

  /// Login del preventa autenticado actualmente, o null si no hay sesión.
  /// Filtra qué pedidos se ven en la lista y se intentan subir: en un
  /// dispositivo compartido cada preventa solo ve y envía los suyos. Lo
  /// actualiza [AuthProvider] al iniciar/cerrar sesión.
  String? _usuarioActivo;

  String get filtro => _filtro;
  bool get soloPendientes => _soloPendientes;
  bool get cargando => _cargando;
  String? get usuarioActivo => _usuarioActivo;

  /// Establece el preventa autenticado y recarga la lista para que el
  /// filtrado se aplique inmediatamente. Llamar con null cuando se cierra
  /// sesión; con el login del preventa al iniciarla o al arrancar la app
  /// con sesión persistida.
  Future<void> setUsuarioActivo(String? login) async {
    if (login == _usuarioActivo) return;
    _usuarioActivo = login;
    await recargarDesdeLocal();
  }

  /// Pedidos a mostrar tras aplicar el buscador y el filtro "solo
  /// pendientes". Sin filtros, devuelve todos descendiendo por fecha.
  List<Pedido> get pedidos {
    final texto = _filtro.trim().toLowerCase();
    return _todos.where((p) {
      if (_soloPendientes && p.estadoSync == EstadoSync.sincronizado) {
        return false;
      }
      if (texto.isEmpty) return true;
      bool casa(String? v) => v != null && v.toLowerCase().contains(texto);
      return casa(p.numero) || casa(p.clienteNombre);
    }).toList(growable: false);
  }

  /// Número de pedidos pendientes de subir al servidor.
  int get pendientes =>
      _todos.where((p) => p.estadoSync == EstadoSync.pendente).length;

  /// Número de pedidos con error (incluye "esperando cliente").
  int get conError =>
      _todos.where((p) => p.estadoSync == EstadoSync.erro).length;

  /// Devuelve todos los pedidos en un estado de sincronización concreto,
  /// sin aplicar los filtros activos de la lista principal. Lo usa la
  /// pantalla de estado de sincronización para listar pendientes y errores
  /// con independencia de lo que el usuario tenga filtrado en otra vista.
  List<Pedido> pedidosPorEstado(EstadoSync estado) {
    return _todos.where((p) => p.estadoSync == estado).toList(growable: false);
  }

  /// Carga la lista completa desde SQLite. Se llama al arrancar la app y
  /// tras cada operación que la modifique (alta, eliminación, sincronización).
  /// Filtra por [_usuarioActivo] si está definido: cada preventa solo ve
  /// los suyos.
  Future<void> recargarDesdeLocal() async {
    _cargando = true;
    notifyListeners();
    _todos = await _dao.listar(usuarioLogin: _usuarioActivo);
    _cargando = false;
    notifyListeners();
  }

  void aplicarFiltro(String nuevo) {
    if (nuevo == _filtro) return;
    _filtro = nuevo;
    notifyListeners();
  }

  void aplicarSoloPendientes(bool valor) {
    if (valor == _soloPendientes) return;
    _soloPendientes = valor;
    notifyListeners();
  }

  /// Recupera un pedido por su id local desde SQLite (con sus líneas).
  Future<Pedido?> obtener(String idLocal) => _dao.obtenerPorIdLocal(idLocal);

  /// Da de alta un pedido local nuevo a partir del cliente y las líneas que
  /// trae el formulario. Genera todos los UUIDs (pedido + líneas), calcula
  /// los totales en Dart como previsualización y lo guarda en SQLite en
  /// estado PENDENTE.
  ///
  /// No llama al servidor: la app es offline-first, igual que con clientes.
  /// El pedido sube al backend cuando el usuario pulsa Sincronizar; en ese
  /// momento el backend, a su vez, lo enviará inmediatamente a Odoo sin
  /// esperar a su scheduler periódico.
  ///
  /// Devuelve el pedido tal como quedó persistido en local.
  Future<Pedido> crearPedidoLocal({
    required Cliente cliente,
    required List<BorradorLinea> lineas,
    String? observaciones,
  }) async {
    if (lineas.isEmpty) {
      throw ArgumentError('Un pedido debe tener al menos una línea');
    }

    final ahora = DateTime.now();
    final idLocal = _uuid.v4();

    final lineasPedido = lineas
        .map((b) => LineaPedido(
              idLocal: _uuid.v4(),
              pedidoIdLocal: idLocal,
              productoId: b.productoId,
              codigoProducto: b.codigoProducto,
              descripcion: b.descripcion,
              precio: b.precio,
              iva: b.iva,
              recargoEquivalencia: b.recargoEquivalencia,
              cantidade: b.cantidade,
              subtotal: b.subtotal,
            ))
        .toList(growable: false);

    final totales = _calcularTotales(lineasPedido);

    final pedido = Pedido(
      idLocal: idLocal,
      fecha: ahora,
      clienteIdLocal: cliente.idLocal,
      clienteIdServidor: cliente.idServidor,
      clienteNombre: cliente.razonSocial ?? cliente.nombreComercial,
      lineas: lineasPedido,
      totalBase: totales.base,
      totalIva: totales.iva,
      totalRE: totales.re,
      total: totales.total,
      estadoPedido: EstadoPedido.borrador,
      estadoSync: EstadoSync.pendente,
      usuarioLogin: _usuarioActivo,
      observaciones: _limpiarObservaciones(observaciones),
      actualizadoEn: ahora,
      creadoEn: ahora,
    );

    await _dao.insertarLocal(pedido);
    await recargarDesdeLocal();
    return pedido;
  }

  /// Actualiza un pedido local existente (no sincronizado) con un nuevo
  /// cliente y nuevas líneas. Recalcula los totales y deja el pedido en
  /// BORRADOR + PENDENTE, limpiando cualquier error anterior — el siguiente
  /// envío reintentará desde cero.
  ///
  /// Solo se permite si el pedido aún no tiene `id_servidor`: una vez
  /// sincronizado, las modificaciones las hace Odoo y la app no debe alterar
  /// el estado local.
  Future<Pedido> actualizarPedidoLocal({
    required String idLocal,
    required Cliente cliente,
    required List<BorradorLinea> lineas,
    String? observaciones,
  }) async {
    if (lineas.isEmpty) {
      throw ArgumentError('Un pedido debe tener al menos una línea');
    }
    final existente = await _dao.obtenerPorIdLocal(idLocal);
    if (existente == null) {
      throw StateError('Pedido no encontrado: $idLocal');
    }
    if (existente.idServidor != null) {
      throw StateError('No se puede editar un pedido ya sincronizado');
    }

    final ahora = DateTime.now();
    final lineasPedido = lineas
        .map((b) => LineaPedido(
              idLocal: _uuid.v4(),
              pedidoIdLocal: idLocal,
              productoId: b.productoId,
              codigoProducto: b.codigoProducto,
              descripcion: b.descripcion,
              precio: b.precio,
              iva: b.iva,
              recargoEquivalencia: b.recargoEquivalencia,
              cantidade: b.cantidade,
              subtotal: b.subtotal,
            ))
        .toList(growable: false);

    final totales = _calcularTotales(lineasPedido);

    final pedido = Pedido(
      idLocal: idLocal,
      fecha: existente.fecha,
      clienteIdLocal: cliente.idLocal,
      clienteIdServidor: cliente.idServidor,
      clienteNombre: cliente.razonSocial ?? cliente.nombreComercial,
      lineas: lineasPedido,
      totalBase: totales.base,
      totalIva: totales.iva,
      totalRE: totales.re,
      total: totales.total,
      estadoPedido: EstadoPedido.borrador,
      estadoSync: EstadoSync.pendente,
      // Preservamos el creador original (no lo cambiamos porque otro
      // preventa edite el pedido — caso teórico, en la práctica solo lo edita
      // quien lo creó).
      usuarioLogin: existente.usuarioLogin,
      observaciones: _limpiarObservaciones(observaciones),
      actualizadoEn: ahora,
      creadoEn: existente.creadoEn,
    );

    await _dao.actualizar(pedido);
    await recargarDesdeLocal();
    return pedido;
  }

  /// Normaliza el texto de observaciones para guardar en local: trim y null
  /// si queda vacío. Si la cadena es null, devuelve null tal cual. Evita
  /// guardar espacios sueltos o cadenas vacías que luego se enviarían a la
  /// API y a Odoo.
  String? _limpiarObservaciones(String? valor) {
    if (valor == null) return null;
    final limpio = valor.trim();
    return limpio.isEmpty ? null : limpio;
  }

  /// Reintenta el envío al servidor de un pedido en estado ERRO o PENDENTE
  /// (típicamente desde la pantalla de estado de sincronización). Devuelve
  /// el resultado del intento para que la UI muestre el mensaje correcto.
  ///
  /// Tras el intento se recarga la lista desde SQLite, así la UI refleja
  /// inmediatamente el nuevo estado (sincronizado, sigue en error, etc.).
  Future<ResultadoEnvioPedido> reintentarPedido(String idLocal) async {
    final pedido = await _dao.obtenerPorIdLocal(idLocal);
    if (pedido == null) return ResultadoEnvioPedido.errorRecuperable;
    final resultado = await _syncService.reenviarUno(pedido);
    await recargarDesdeLocal();
    return resultado;
  }

  /// Envía todos los pedidos pendientes y los que quedaron en error al
  /// servidor. Pensado para llamarse desde el [SyncProvider] como parte de
  /// la sincronización general; al terminar refresca la lista en memoria
  /// para que los cambios de estado se reflejen en la UI.
  Future<ResultadoEnvioPedidos> enviarPendientesAlServidor() async {
    final resultado =
        await _syncService.enviarPendientes(usuarioLogin: _usuarioActivo);
    await recargarDesdeLocal();
    return resultado;
  }

  /// Elimina un pedido local. Solo se permite si está en BORRADOR + PENDENTE
  /// (todavía no subido al servidor): no permitimos borrar pedidos ya
  /// confirmados desde la app, esa decisión la toma Odoo.
  Future<bool> eliminarPedidoLocal(String idLocal) async {
    final pedido = await _dao.obtenerPorIdLocal(idLocal);
    if (pedido == null) return false;
    if (pedido.idServidor != null) return false;

    await _dao.eliminarPorIdLocal(idLocal);
    await recargarDesdeLocal();
    return true;
  }

  /// Sincroniza los pedidos del servidor a la BD local (descendente). Trae
  /// los modificados desde [desde] (o todos si es null) y los upserta.
  ///
  /// Para cada pedido del servidor:
  ///  - Resuelve el UUID local del cliente buscando por `id_servidor` en la
  ///    tabla de clientes. Si el cliente no está aún en local, se omite el
  ///    pedido (no se persiste): se persistirá la próxima vez una vez el
  ///    cliente esté sincronizado descendentemente.
  ///  - Genera UUIDs nuevos para las líneas (el backend no tiene UUIDs).
  Future<int> sincronizarDesdeServidor(DateTime? desde) async {
    final lista = await _service.listar(modificadoDesde: desde);

    int procesados = 0;
    for (final json in lista) {
      final clienteResumen = json['cliente'] as Map<String, dynamic>;
      final clienteIdServidor = clienteResumen['id'] as int?;
      if (clienteIdServidor == null) continue;

      final clienteLocal =
          await _clientesDao.obtenerPorIdServidor(clienteIdServidor);
      if (clienteLocal == null) {
        // Cliente todavía no sincronizado en local: nos saltamos el pedido.
        // Cuando el cliente baje en una vuelta posterior, el pedido se
        // procesará entonces.
        continue;
      }

      final idLocalPedido = _uuid.v4();
      final lineasJson = (json['lineas'] as List<dynamic>?) ?? const [];
      final lineas = lineasJson
          .cast<Map<String, dynamic>>()
          .map((l) => LineaPedido.desdeServidor(
                l,
                idLocal: _uuid.v4(),
                pedidoIdLocal: idLocalPedido,
              ))
          .toList();

      final pedido = Pedido.desdeServidor(
        json,
        idLocal: idLocalPedido,
        clienteIdLocal: clienteLocal.idLocal,
        lineas: lineas,
      );
      await _dao.upsertDesdeServidor(pedido);
      procesados++;
    }

    await recargarDesdeLocal();

    if (kDebugMode) {
      debugPrint('PedidosProvider: sincronizados $procesados pedidos '
          '${desde == null ? '(carga completa)' : '(desde $desde)'}');
    }

    return procesados;
  }

  /// Suma los totales de las líneas para construir los totales de cabecera.
  _Totales _calcularTotales(List<LineaPedido> lineas) {
    double base = 0;
    double iva = 0;
    double re = 0;
    for (final l in lineas) {
      final b = l.precio * l.cantidade;
      base += b;
      iva += b * l.iva / 100;
      re += b * l.recargoEquivalencia / 100;
    }
    final total = base + iva + re;
    return _Totales(
      base: double.parse(base.toStringAsFixed(2)),
      iva: double.parse(iva.toStringAsFixed(2)),
      re: double.parse(re.toStringAsFixed(2)),
      total: double.parse(total.toStringAsFixed(2)),
    );
  }
}

/// Totales agregados de un pedido, redondeados a 2 decimales.
class _Totales {
  final double base;
  final double iva;
  final double re;
  final double total;
  const _Totales({
    required this.base,
    required this.iva,
    required this.re,
    required this.total,
  });
}
