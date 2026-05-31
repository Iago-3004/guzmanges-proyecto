import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/db/dao/clientes_dao.dart';
import '../core/db/dao/pedidos_dao.dart';
import '../dto/crear_pedido_request.dart';
import '../models/cliente.dart' show Cliente, EstadoSync;
import '../models/linea_pedido.dart';
import '../models/pedido.dart';
import '../services/pedidos_service.dart';

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
  final Uuid _uuid;

  PedidosProvider(this._service, this._dao, this._clientesDao,
      {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  List<Pedido> _todos = const [];
  String _filtro = '';
  bool _soloPendientes = false;
  bool _cargando = false;

  String get filtro => _filtro;
  bool get soloPendientes => _soloPendientes;
  bool get cargando => _cargando;

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

  /// Carga la lista completa desde SQLite. Se llama al arrancar la app y
  /// tras cada operación que la modifique (alta, eliminación, sincronización).
  Future<void> recargarDesdeLocal() async {
    _cargando = true;
    notifyListeners();
    _todos = await _dao.listar();
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
  /// A continuación se intenta subir al servidor inmediatamente: si tiene
  /// éxito, la fila pasa a SINCRONIZADO con los totales definitivos
  /// devueltos por la API; si falla, queda PENDENTE y el [SyncProvider] lo
  /// reintentará en la próxima sincronización.
  ///
  /// Devuelve el pedido tal como quedó en SQLite (con o sin id de servidor).
  Future<Pedido> crearPedidoLocal({
    required Cliente cliente,
    required List<BorradorLinea> lineas,
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
      actualizadoEn: ahora,
      creadoEn: ahora,
    );

    await _dao.insertarLocal(pedido);
    await _intentarEnviarInmediato(pedido);
    await recargarDesdeLocal();

    // Tras la recarga, devolver el pedido refrescado por si el envío
    // inmediato lo dejó SINCRONIZADO con totales definitivos.
    return (await _dao.obtenerPorIdLocal(idLocal)) ?? pedido;
  }

  /// Intenta enviar un pedido recién creado al servidor. Solo se llega a
  /// llamar si el cliente ya tiene `id_servidor`: si no, se omite y el
  /// pedido queda PENDENTE para que la próxima sincronización lo trate
  /// como "esperando cliente".
  Future<void> _intentarEnviarInmediato(Pedido pedido) async {
    if (pedido.clienteIdServidor == null) {
      if (kDebugMode) {
        debugPrint('PedidosProvider: cliente sin idServidor — pedido ${pedido.idLocal} '
            'queda PENDENTE para la próxima sincronización');
      }
      return;
    }

    try {
      final request = CrearPedidoRequest(
        clienteId: pedido.clienteIdServidor!,
        lineas: pedido.lineas
            .map((l) => CrearLineaRequest(
                  productoId: l.productoId,
                  cantidade: l.cantidade,
                  precio: l.precio,
                  iva: l.iva,
                  recargoEquivalencia: l.recargoEquivalencia,
                ))
            .toList(),
      );
      final json = await _service.crear(request);
      await _dao.marcarSincronizado(
        idLocal: pedido.idLocal,
        idServidor: json['id'] as int,
        idOdoo: json['idOdoo'] as String?,
        numero: json['numero'] as String?,
        estadoPedido:
            EstadoPedido.desdeBackend(json['estadoPedido'] as String?),
        totalBase: (json['totalBase'] as num?)?.toDouble() ?? 0.0,
        totalIva: (json['totalIva'] as num?)?.toDouble() ?? 0.0,
        totalRE: (json['totalRE'] as num?)?.toDouble() ?? 0.0,
        total: (json['total'] as num?)?.toDouble() ?? 0.0,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PedidosProvider: envío inmediato falló para pedido ${pedido.idLocal}: $e');
      }
      // El pedido queda PENDENTE (es su estado actual). El SyncProvider lo
      // reintentará en la próxima sincronización.
    }
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
