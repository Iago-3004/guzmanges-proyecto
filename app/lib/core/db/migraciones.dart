import 'package:sqflite/sqflite.dart';

/// Migraciones SQL de la base de datos local.
///
/// Centraliza los scripts por versión. [DatabaseHelper] los aplica en orden
/// durante `onCreate` (todos desde la 1 hasta la última) o `onUpgrade` (solo
/// las versiones nuevas respecto a la instalada).
///
/// Para añadir una nueva versión, simplemente añade una clave al mapa
/// [_porVersion] con la lista de sentencias SQL a ejecutar.
class Migraciones {
  Migraciones._();

  /// Versión actual del esquema. Hay que incrementarla cada vez que se añada
  /// una nueva versión al mapa [_porVersion].
  static const int versionActual = 1;

  /// Sentencias SQL agrupadas por versión.
  ///
  /// - **v1**: tabla `sync_metadata` (clave/valor para guardar la marca temporal
  ///   de la última sincronización completa con el servidor).
  static const Map<int, List<String>> _porVersion = {
    1: [
      '''
      CREATE TABLE sync_metadata (
        clave TEXT PRIMARY KEY,
        valor TEXT NOT NULL
      )
      ''',
    ],
  };

  /// Aplica todas las migraciones desde [desde] (exclusivo) hasta [hasta]
  /// (inclusivo) sobre la base de datos [db].
  ///
  /// - En `onCreate` se llama con `desde=0, hasta=versionActual`.
  /// - En `onUpgrade` se llama con `desde=oldVersion, hasta=newVersion`.
  static Future<void> aplicar(Database db, int desde, int hasta) async {
    for (int version = desde + 1; version <= hasta; version++) {
      final sentencias = _porVersion[version];
      if (sentencias == null) continue;
      for (final sql in sentencias) {
        await db.execute(sql);
      }
    }
  }
}
