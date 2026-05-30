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
  static const int versionActual = 3;

  /// Sentencias SQL agrupadas por versión.
  ///
  /// - **v1**: tabla `sync_metadata` (clave/valor para guardar la marca temporal
  ///   de la última sincronización completa con el servidor).
  /// - **v2**: tablas `modos_pago` y `condiciones_pago` (catálogos maestros
  ///   cacheados desde el servidor para alimentar los selectores en la alta
  ///   de clientes).
  /// - **v3**: tabla `clientes` con identidad dual `id_local` (UUID generado
  ///   en el móvil) + `id_servidor` (nullable mientras la alta no se haya
  ///   subido al servidor). Estado de sincronización con los mismos valores
  ///   que el enum `EstadoSync` del backend (PENDENTE/SINCRONIZADO/ERRO).
  static const Map<int, List<String>> _porVersion = {
    1: [
      '''
      CREATE TABLE sync_metadata (
        clave TEXT PRIMARY KEY,
        valor TEXT NOT NULL
      )
      ''',
    ],
    2: [
      '''
      CREATE TABLE modos_pago (
        id INTEGER PRIMARY KEY,
        descripcion TEXT NOT NULL,
        activo INTEGER NOT NULL DEFAULT 1,
        actualizado_en INTEGER NOT NULL
      )
      ''',
      '''
      CREATE TABLE condiciones_pago (
        id INTEGER PRIMARY KEY,
        descripcion TEXT NOT NULL,
        activo INTEGER NOT NULL DEFAULT 1,
        actualizado_en INTEGER NOT NULL
      )
      ''',
    ],
    3: [
      '''
      CREATE TABLE clientes (
        id_local TEXT PRIMARY KEY,
        id_servidor INTEGER UNIQUE,
        id_odoo TEXT,
        nombre_comercial TEXT NOT NULL,
        razon_social TEXT,
        cif TEXT,
        direccion TEXT,
        localidad TEXT,
        codigo_postal TEXT,
        provincia TEXT,
        telefono TEXT,
        movil TEXT,
        email TEXT,
        modo_pago_id INTEGER,
        modo_pago_descripcion TEXT,
        condicion_pago_id INTEGER,
        condicion_pago_descripcion TEXT,
        comercial TEXT,
        activo INTEGER NOT NULL DEFAULT 1,
        estado_sync TEXT NOT NULL
          CHECK (estado_sync IN ('SINCRONIZADO','PENDENTE','ERRO')),
        mensaje_error TEXT,
        coincidencias_409 TEXT,
        actualizado_en INTEGER NOT NULL,
        creado_en INTEGER NOT NULL
      )
      ''',
      'CREATE INDEX idx_clientes_estado ON clientes(estado_sync)',
      'CREATE INDEX idx_clientes_nombre ON clientes(nombre_comercial COLLATE NOCASE)',
      'CREATE INDEX idx_clientes_activo ON clientes(activo)',
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
