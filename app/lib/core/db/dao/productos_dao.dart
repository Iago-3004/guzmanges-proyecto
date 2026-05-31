import 'package:sqflite/sqflite.dart';

import '../../../models/producto.dart';
import '../database_helper.dart';

/// Acceso a SQLite para el catálogo de productos.
///
/// Productos son de solo lectura desde la app: la única operación de escritura
/// es el [upsert] que aplica la sincronización descendente.
class ProductosDao {
  ProductosDao();

  static const String _tabla = 'productos';

  Database get _db => DatabaseHelper.instancia.db;

  /// Lista los productos cacheados, ordenados por descripción.
  ///
  /// El filtrado por texto se hace en Dart (no en SQL), porque el `LIKE` de
  /// SQLite con `COLLATE NOCASE` solo ignora mayúsculas/minúsculas en ASCII
  /// y no reconoce tildes ni `Ñ`/`ñ`.
  Future<List<Producto>> listar() async {
    final filas = await _db.query(
      _tabla,
      orderBy: 'descripcion COLLATE NOCASE',
    );
    return filas.map(Producto.fromMap).toList(growable: false);
  }

  /// Obtiene un producto por su id del servidor, o null si no existe en local.
  Future<Producto?> obtenerPorId(int id) async {
    final filas = await _db.query(
      _tabla,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (filas.isEmpty) return null;
    return Producto.fromMap(filas.first);
  }

  /// Inserta o reemplaza una lista de productos en una única transacción.
  /// La PK es el id del servidor, por lo que un upsert se resuelve con
  /// `ConflictAlgorithm.replace` sin necesidad de comprobar antes si existe.
  Future<void> upsert(List<Producto> productos) async {
    if (productos.isEmpty) return;
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final producto in productos) {
        batch.insert(
          _tabla,
          producto.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Devuelve cuántos productos hay cacheados. Útil para mostrar contadores
  /// o decidir si lanzar una sincronización inicial al abrir el catálogo.
  Future<int> contar() async {
    final filas =
        await _db.rawQuery('SELECT COUNT(*) AS total FROM $_tabla');
    return (filas.first['total'] as int?) ?? 0;
  }
}
