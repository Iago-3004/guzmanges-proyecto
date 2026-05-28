import 'package:sqflite/sqflite.dart';

import '../../../models/condicion_pago.dart';
import '../../../models/modo_pago.dart';
import '../database_helper.dart';

/// Acceso a SQLite para los catálogos de pago (modos y condiciones).
///
/// Ambas tablas tienen la misma forma (id/descripcion/activo/actualizado_en)
/// pero las llevamos por separado por claridad de dominio.
class CatalogosDao {
  CatalogosDao();

  static const String _tablaModos = 'modos_pago';
  static const String _tablaCondiciones = 'condiciones_pago';

  Database get _db => DatabaseHelper.instancia.db;

  // ---------------------------------------------------------------------------
  // Modos de pago
  // ---------------------------------------------------------------------------

  /// Devuelve los modos de pago cacheados, ordenados por descripción.
  ///
  /// Por defecto solo los activos; pasa [soloActivos] como `false` para
  /// recuperar también los desactivados (útil al resolver pedidos antiguos).
  Future<List<ModoPago>> listarModos({bool soloActivos = true}) async {
    final filas = await _db.query(
      _tablaModos,
      where: soloActivos ? 'activo = 1' : null,
      orderBy: 'descripcion COLLATE NOCASE',
    );
    return filas.map(ModoPago.fromMap).toList(growable: false);
  }

  /// Inserta o reemplaza la lista de modos de pago. Se ejecuta en una única
  /// transacción para evitar estados intermedios visibles.
  Future<void> upsertModos(List<ModoPago> modos) async {
    if (modos.isEmpty) return;
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final modo in modos) {
        batch.insert(
          _tablaModos,
          modo.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  // ---------------------------------------------------------------------------
  // Condiciones de pago
  // ---------------------------------------------------------------------------

  /// Devuelve las condiciones de pago cacheadas, ordenadas por descripción.
  Future<List<CondicionPago>> listarCondiciones({bool soloActivos = true}) async {
    final filas = await _db.query(
      _tablaCondiciones,
      where: soloActivos ? 'activo = 1' : null,
      orderBy: 'descripcion COLLATE NOCASE',
    );
    return filas.map(CondicionPago.fromMap).toList(growable: false);
  }

  /// Inserta o reemplaza la lista de condiciones de pago.
  Future<void> upsertCondiciones(List<CondicionPago> condiciones) async {
    if (condiciones.isEmpty) return;
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final cond in condiciones) {
        batch.insert(
          _tablaCondiciones,
          cond.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }
}
