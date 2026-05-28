import 'package:sqflite/sqflite.dart';

import '../database_helper.dart';

/// DAO mínimo clave/valor para los metadatos de sincronización.
///
/// Por ahora se usa una única clave [claveUltimaSync] que guarda la marca
/// temporal (ISO-8601 local) de la última sincronización completa con el
/// servidor. En el futuro podrán añadirse más claves para otros metadatos.
class SyncMetadataDao {
  SyncMetadataDao();

  static const String _tabla = 'sync_metadata';

  /// Clave que guarda la marca temporal de la última sincronización completa.
  /// Se pasa como `?modificadoDesde=...` en la siguiente sincronización para
  /// que el servidor devuelva solo lo modificado desde entonces.
  static const String claveUltimaSync = 'ultimaSync';

  Database get _db => DatabaseHelper.instancia.db;

  /// Devuelve el valor asociado a [clave], o `null` si no existe.
  Future<String?> obtener(String clave) async {
    final filas = await _db.query(
      _tabla,
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: [clave],
      limit: 1,
    );
    if (filas.isEmpty) return null;
    return filas.first['valor'] as String?;
  }

  /// Guarda (o reemplaza) el valor asociado a [clave].
  Future<void> guardar(String clave, String valor) async {
    await _db.insert(
      _tabla,
      {'clave': clave, 'valor': valor},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Devuelve la marca temporal de la última sincronización completa, o `null`
  /// si todavía no se ha hecho ninguna.
  Future<DateTime?> obtenerUltimaSync() async {
    final valor = await obtener(claveUltimaSync);
    if (valor == null) return null;
    return DateTime.tryParse(valor);
  }

  /// Guarda la marca temporal de la última sincronización completa.
  ///
  /// El valor se serializa en formato ISO-8601 local (sin zona horaria), que
  /// es lo que espera el filtro `?modificadoDesde=` del backend.
  Future<void> guardarUltimaSync(DateTime fecha) async {
    await guardar(claveUltimaSync, fecha.toIso8601String());
  }
}
