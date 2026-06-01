import 'package:sqflite/sqflite.dart';

import '../../../models/cliente.dart' show EstadoSync;
import '../../../models/linea_pedido.dart';
import '../../../models/pedido.dart';
import '../database_helper.dart';

/// Acceso a SQLite para los pedidos y sus líneas.
///
/// Las operaciones que tocan cabecera y líneas a la vez se hacen en
/// transacción para que la BD no quede a medias si algo falla a mitad.
class PedidosDao {
  PedidosDao();

  static const String _tablaPedidos = 'pedidos';
  static const String _tablaLineas = 'lineas_pedido';

  Database get _db => DatabaseHelper.instancia.db;

  /// Lista los pedidos en SQLite, descendentes por fecha. Para cada uno
  /// carga sus líneas en una segunda consulta (en lugar de hacer un join
  /// con `GROUP_CONCAT`, que se complica con tantos campos numéricos).
  Future<List<Pedido>> listar() async {
    final filas = await _db.query(_tablaPedidos, orderBy: 'fecha DESC');
    final pedidos = <Pedido>[];
    for (final fila in filas) {
      final idLocal = fila['id_local'] as String;
      final lineas = await _listarLineas(idLocal);
      pedidos.add(Pedido.fromMap(fila, lineas: lineas));
    }
    return pedidos;
  }

  /// Obtiene un pedido por su id local con sus líneas cargadas, o null si
  /// no existe.
  Future<Pedido?> obtenerPorIdLocal(String idLocal) async {
    final filas = await _db.query(
      _tablaPedidos,
      where: 'id_local = ?',
      whereArgs: [idLocal],
      limit: 1,
    );
    if (filas.isEmpty) return null;
    final lineas = await _listarLineas(idLocal);
    return Pedido.fromMap(filas.first, lineas: lineas);
  }

  /// Lista los pedidos pendientes de subir, en orden FIFO. La cola se
  /// determina por `id_servidor IS NULL` (no por `estado_sync`) por el
  /// mismo motivo que en clientes: el campo de estado puede sobreescribirse
  /// en una sincronización descendente y la cola debe ser robusta a eso.
  Future<List<Pedido>> listarPendientesDeEnvio() async {
    final filas = await _db.query(
      _tablaPedidos,
      where: 'id_servidor IS NULL',
      orderBy: 'creado_en ASC',
    );
    final pedidos = <Pedido>[];
    for (final fila in filas) {
      final idLocal = fila['id_local'] as String;
      final lineas = await _listarLineas(idLocal);
      pedidos.add(Pedido.fromMap(fila, lineas: lineas));
    }
    return pedidos;
  }

  /// Inserta un pedido nuevo (cabecera + líneas) en una transacción.
  ///
  /// Las líneas deben venir con su `pedido_id_local` ya apuntando al UUID
  /// del pedido. No se valida aquí porque la consistencia se garantiza al
  /// construir el [Pedido] en el provider.
  Future<void> insertarLocal(Pedido pedido) async {
    await _db.transaction((txn) async {
      await txn.insert(
        _tablaPedidos,
        pedido.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      for (final linea in pedido.lineas) {
        await txn.insert(_tablaLineas, linea.toMap());
      }
    });
  }

  /// Upsert de un pedido que viene del servidor. Si ya existe en local
  /// (por su `id_servidor`), reusa el `id_local` y `creado_en` existentes;
  /// si no, se inserta tal cual.
  ///
  /// En ambos casos se reescriben las líneas completas: el backend es la
  /// fuente de verdad tras la confirmación. Los pedidos locales sin
  /// `id_servidor` nunca se ven afectados.
  Future<void> upsertDesdeServidor(Pedido pedido) async {
    await _db.transaction((txn) async {
      String idLocalFinal = pedido.idLocal;
      int creadoEn = pedido.creadoEn.millisecondsSinceEpoch;

      final existente = await txn.query(
        _tablaPedidos,
        columns: ['id_local', 'creado_en'],
        where: 'id_servidor = ?',
        whereArgs: [pedido.idServidor],
        limit: 1,
      );

      final mapa = pedido.toMap();
      if (existente.isNotEmpty) {
        idLocalFinal = existente.first['id_local'] as String;
        creadoEn = existente.first['creado_en'] as int;
        mapa['id_local'] = idLocalFinal;
        mapa['creado_en'] = creadoEn;
        await txn.update(
          _tablaPedidos,
          mapa,
          where: 'id_local = ?',
          whereArgs: [idLocalFinal],
        );
        // Las líneas se reemplazan: borrar las existentes y volver a
        // insertar las nuevas con sus UUIDs (que pueden ser distintos a los
        // anteriores; al venir del servidor reciben UUIDs nuevos).
        await txn.delete(
          _tablaLineas,
          where: 'pedido_id_local = ?',
          whereArgs: [idLocalFinal],
        );
      } else {
        await txn.insert(_tablaPedidos, mapa);
      }

      for (final linea in pedido.lineas) {
        final mapaLinea = linea.toMap()..['pedido_id_local'] = idLocalFinal;
        await txn.insert(_tablaLineas, mapaLinea);
      }
    });
  }

  /// Actualiza un pedido local existente (cabecera + líneas) en una
  /// transacción. Las líneas se reemplazan en bloque: se borran las
  /// existentes y se insertan las nuevas con sus UUIDs. Pensado para la
  /// edición de un pedido todavía no sincronizado, así que se asume que la
  /// fila ya existe (si no, el update se aplica sobre 0 filas y el insert
  /// de líneas no escribe nada útil).
  Future<void> actualizar(Pedido pedido) async {
    await _db.transaction((txn) async {
      await txn.update(
        _tablaPedidos,
        pedido.toMap(),
        where: 'id_local = ?',
        whereArgs: [pedido.idLocal],
      );
      await txn.delete(
        _tablaLineas,
        where: 'pedido_id_local = ?',
        whereArgs: [pedido.idLocal],
      );
      for (final linea in pedido.lineas) {
        await txn.insert(_tablaLineas, linea.toMap());
      }
    });
  }

  /// Marca un pedido como sincronizado tras el envío al servidor. Rellena
  /// `id_servidor`, `id_odoo`, `numero` y los totales devueltos por la
  /// API, y limpia errores anteriores.
  Future<void> marcarSincronizado({
    required String idLocal,
    required int idServidor,
    String? idOdoo,
    String? numero,
    required EstadoPedido estadoPedido,
    required double totalBase,
    required double totalIva,
    required double totalRE,
    required double total,
  }) async {
    await _db.update(
      _tablaPedidos,
      {
        'id_servidor': idServidor,
        'id_odoo': idOdoo,
        'numero': numero,
        'estado_pedido': estadoPedido.nombreBackend,
        'estado_sync': EstadoSync.sincronizado.nombreBackend,
        'mensaje_error': null,
        'total_base': totalBase,
        'total_iva': totalIva,
        'total_re': totalRE,
        'total': total,
        'actualizado_en': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  /// Marca un pedido como ERRO con un mensaje legible.
  Future<void> marcarError({
    required String idLocal,
    required String mensaje,
  }) async {
    await _db.update(
      _tablaPedidos,
      {
        'estado_sync': EstadoSync.erro.nombreBackend,
        'mensaje_error': mensaje,
        'actualizado_en': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  /// Elimina un pedido y sus líneas (la cascada del FK ya las borra, pero
  /// las eliminamos explícitamente porque el `PRAGMA foreign_keys` no se
  /// activa por defecto en sqflite y no queremos depender de él).
  Future<int> eliminarPorIdLocal(String idLocal) async {
    return _db.transaction((txn) async {
      await txn.delete(
        _tablaLineas,
        where: 'pedido_id_local = ?',
        whereArgs: [idLocal],
      );
      return txn.delete(
        _tablaPedidos,
        where: 'id_local = ?',
        whereArgs: [idLocal],
      );
    });
  }

  /// Cuenta los pedidos en un estado concreto. Útil para contadores en la
  /// home y en el banner persistente.
  Future<int> contarPorEstado(EstadoSync estado) async {
    final filas = await _db.rawQuery(
      'SELECT COUNT(*) AS total FROM $_tablaPedidos WHERE estado_sync = ?',
      [estado.nombreBackend],
    );
    return (filas.first['total'] as int?) ?? 0;
  }

  /// Lista las líneas de un pedido, en el orden de inserción (la PK es
  /// un UUID, así que no aporta orden — usamos rowid implícito).
  Future<List<LineaPedido>> _listarLineas(String pedidoIdLocal) async {
    final filas = await _db.query(
      _tablaLineas,
      where: 'pedido_id_local = ?',
      whereArgs: [pedidoIdLocal],
      orderBy: 'rowid ASC',
    );
    return filas.map(LineaPedido.fromMap).toList(growable: false);
  }
}
