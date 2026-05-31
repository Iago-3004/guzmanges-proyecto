import 'package:sqflite/sqflite.dart';

import '../../../models/cliente.dart';
import '../database_helper.dart';

/// Acceso a SQLite para la tabla de clientes.
class ClientesDao {
  ClientesDao();

  static const String _tabla = 'clientes';

  Database get _db => DatabaseHelper.instancia.db;

  /// Lista los clientes en SQLite, ordenados por nombre comercial.
  ///
  /// El filtrado por texto se hace en Dart (no en SQL), porque el `LIKE` de
  /// SQLite con `COLLATE NOCASE` solo ignora mayúsculas/minúsculas en ASCII;
  /// no reconoce que `Ñ`/`ñ` o las vocales con tilde son la misma letra.
  ///
  /// Si [soloActivos] es true (por defecto), excluye los desactivados.
  Future<List<Cliente>> listar({bool soloActivos = true}) async {
    final filas = await _db.query(
      _tabla,
      where: soloActivos ? 'activo = 1' : null,
      orderBy: 'nombre_comercial COLLATE NOCASE',
    );
    return filas.map(Cliente.fromMap).toList(growable: false);
  }

  /// Obtiene un cliente por su id local (UUID), o null si no existe.
  Future<Cliente?> obtenerPorIdLocal(String idLocal) async {
    final filas = await _db.query(
      _tabla,
      where: 'id_local = ?',
      whereArgs: [idLocal],
      limit: 1,
    );
    if (filas.isEmpty) return null;
    return Cliente.fromMap(filas.first);
  }

  /// Obtiene un cliente por su id del servidor, o null si aún no se ha
  /// sincronizado o no existe.
  Future<Cliente?> obtenerPorIdServidor(int idServidor) async {
    final filas = await _db.query(
      _tabla,
      where: 'id_servidor = ?',
      whereArgs: [idServidor],
      limit: 1,
    );
    if (filas.isEmpty) return null;
    return Cliente.fromMap(filas.first);
  }

  /// Lista los clientes que aún no se han subido al servidor, es decir, los
  /// que no tienen `id_servidor`. Se ordenan en orden de creación (FIFO)
  /// para que el envío al servidor respete el orden en que el usuario los
  /// dio de alta.
  ///
  /// Usar `id_servidor IS NULL` (y no `estado_sync IN (...)`) hace que la
  /// cola sea robusta frente al campo `estadoSync` del backend, que tiene
  /// un significado distinto al de la app y podría sobrescribirse en una
  /// sincronización descendente.
  Future<List<Cliente>> listarPendientesDeEnvio() async {
    final filas = await _db.query(
      _tabla,
      where: 'id_servidor IS NULL',
      orderBy: 'creado_en ASC',
    );
    return filas.map(Cliente.fromMap).toList(growable: false);
  }

  /// Busca todos los clientes en local cuyo CIF coincide (sin distinguir
  /// mayúsculas/minúsculas). Incluye activos, inactivos, sincronizados,
  /// pendientes y con error: cualquiera puede ser una coincidencia a avisar.
  Future<List<Cliente>> buscarPorCif(String cif) async {
    final cifNormalizado = cif.trim();
    if (cifNormalizado.isEmpty) return const [];
    final filas = await _db.query(
      _tabla,
      where: 'UPPER(cif) = UPPER(?)',
      whereArgs: [cifNormalizado],
    );
    return filas.map(Cliente.fromMap).toList(growable: false);
  }

  /// Inserta un cliente nuevo (estado PENDENTE) en SQLite. El [Cliente]
  /// ya debe traer un [Cliente.idLocal] generado (UUID v4).
  Future<void> insertarLocal(Cliente cliente) async {
    await _db.insert(
      _tabla,
      cliente.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Upsert de un cliente que viene del servidor. Si ya existe en local
  /// (por su `id_servidor`), reusa el `id_local` existente; si no, se
  /// inserta con el `id_local` que trae el cliente.
  ///
  /// Los clientes locales PENDENTE (sin `id_servidor`) nunca se ven afectados
  /// por esta operación.
  Future<void> upsertDesdeServidor(Cliente cliente) async {
    await _db.transaction((txn) async {
      final existente = await txn.query(
        _tabla,
        columns: ['id_local', 'creado_en'],
        where: 'id_servidor = ?',
        whereArgs: [cliente.idServidor],
        limit: 1,
      );
      if (existente.isNotEmpty) {
        // Reutilizamos el id_local existente y conservamos su creado_en.
        final idLocalExistente = existente.first['id_local'] as String;
        final creadoEnExistente = existente.first['creado_en'] as int;
        final mapa = cliente.toMap()
          ..['id_local'] = idLocalExistente
          ..['creado_en'] = creadoEnExistente;
        await txn.update(
          _tabla,
          mapa,
          where: 'id_local = ?',
          whereArgs: [idLocalExistente],
        );
      } else {
        await txn.insert(_tabla, cliente.toMap());
      }
    });
  }

  /// Marca un cliente local como SINCRONIZADO tras enviarlo con éxito al
  /// servidor: rellena `id_servidor`, `id_odoo` y limpia errores anteriores.
  Future<void> marcarSincronizado({
    required String idLocal,
    required int idServidor,
    String? idOdoo,
  }) async {
    await _db.update(
      _tabla,
      {
        'id_servidor': idServidor,
        'id_odoo': idOdoo,
        'estado_sync': EstadoSync.sincronizado.nombreBackend,
        'mensaje_error': null,
        'coincidencias_409': null,
        'actualizado_en': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  /// Marca un cliente como ERRO con un mensaje legible y, opcionalmente,
  /// el JSON con las coincidencias de un 409.
  Future<void> marcarError({
    required String idLocal,
    required String mensaje,
    String? coincidencias409,
  }) async {
    await _db.update(
      _tabla,
      {
        'estado_sync': EstadoSync.erro.nombreBackend,
        'mensaje_error': mensaje,
        'coincidencias_409': coincidencias409,
        'actualizado_en': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  /// Elimina un cliente de SQLite por su id local. Devuelve cuántas filas se
  /// han borrado (0 si no existía, 1 en caso normal).
  Future<int> eliminarPorIdLocal(String idLocal) async {
    return _db.delete(
      _tabla,
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  /// Cuenta los clientes en un estado concreto. Útil para mostrar contadores
  /// de pendientes o con error sin tener que cargar la lista entera.
  Future<int> contarPorEstado(EstadoSync estado) async {
    final filas = await _db.rawQuery(
      'SELECT COUNT(*) AS total FROM $_tabla WHERE estado_sync = ?',
      [estado.nombreBackend],
    );
    return (filas.first['total'] as int?) ?? 0;
  }
}
