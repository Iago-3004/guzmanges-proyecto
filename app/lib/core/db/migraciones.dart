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
  static const int versionActual = 7;

  /// Sentencias SQL agrupadas por versión.
  ///
  /// - **v1**: tabla `sync_metadata` (clave/valor para metadatos varios,
  ///   en particular la marca temporal de la última sincronización completa).
  /// - **v2**: tablas `modos_pago` y `condiciones_pago` (catálogos maestros
  ///   cacheados desde el servidor).
  /// - **v3**: tabla `clientes` con identidad dual `id_local` (UUID generado
  ///   en el móvil) + `id_servidor` (int del backend, nullable mientras la
  ///   alta no esté subida). El estado de sincronización admite los mismos
  ///   valores que el enum `EstadoSync` del backend (PENDENTE / SINCRONIZADO
  ///   / ERRO).
  /// - **v4**: columna `forzar_envio` en `clientes`. Se pone a 1 cuando el
  ///   usuario ha confirmado "Crear de todas formas" ante un duplicado local,
  ///   para que al subirlo se envíe con `?forzarAlta=true` y el servidor no
  ///   vuelva a preguntar por la misma coincidencia.
  /// - **v5**: columna `posicion_fiscal` en `clientes`. Texto descriptivo
  ///   importado desde Odoo (account.fiscal.position): determina el régimen
  ///   de impuestos del cliente (recargo de equivalencia, exenciones
  ///   intracomunitarias, etc.). La app la muestra como información; los
  ///   cálculos definitivos los aplica Odoo al confirmar el pedido.
  /// - **v6**: columna `recargo_equivalencia` (0/1) en `clientes`. Flag que el
  ///   backend deduce del nombre de la posición fiscal. La app no interpreta
  ///   el texto: pregunta el flag y, si es 1, aplica las tablas legales
  ///   españolas (IVA 21→RE 5.2, 10→1.4, 4→0.5) al calcular las líneas de un
  ///   pedido provisional.
  /// - **v7**: tabla `productos` (catálogo cacheado desde el servidor). Solo
  ///   lectura: el alta y la edición se gestionan en Odoo. La clave primaria
  ///   es directamente el id del servidor (sin UUID local, porque no hay
  ///   altas offline). Incluye el IVA por defecto del producto para que la
  ///   app pueda autocompletar las líneas de pedido sin tener que ir al
  ///   servidor.
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
    4: [
      'ALTER TABLE clientes ADD COLUMN forzar_envio INTEGER NOT NULL DEFAULT 0',
    ],
    5: [
      'ALTER TABLE clientes ADD COLUMN posicion_fiscal TEXT',
    ],
    6: [
      'ALTER TABLE clientes ADD COLUMN recargo_equivalencia INTEGER NOT NULL DEFAULT 0',
    ],
    7: [
      '''
      CREATE TABLE productos (
        id INTEGER PRIMARY KEY,
        id_odoo TEXT,
        referencia TEXT,
        descripcion TEXT NOT NULL,
        codigo_barras TEXT,
        tipo_producto TEXT,
        stock INTEGER,
        precio_venta REAL,
        iva REAL,
        observaciones TEXT,
        actualizado_en INTEGER NOT NULL
      )
      ''',
      'CREATE INDEX idx_productos_descripcion ON productos(descripcion COLLATE NOCASE)',
      'CREATE INDEX idx_productos_referencia ON productos(referencia COLLATE NOCASE)',
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
