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
  static const int versionActual = 9;

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
  /// - **v8**: tablas `pedidos` y `lineas_pedido` con identidad dual `id_local`
  ///   (UUID) + `id_servidor` para soportar el alta offline. El pedido
  ///   referencia al cliente por `cliente_id_local` (FK lógica al UUID del
  ///   cliente, no por id de servidor) para que pueda apuntar a un cliente
  ///   recién dado de alta pendiente de subir. Las líneas se borran en
  ///   cascada (ON DELETE CASCADE) al eliminar la cabecera y guardan el id
  ///   del producto en servidor directamente (los productos son read-only).
  /// - **v9**: columna `usuario_login` en `pedidos`. Identifica al preventa
  ///   que creó el pedido (en alta local) o al que pertenece según el
  ///   backend (en sincronización descendente). La app filtra la lista por
  ///   este campo cuando hay un preventa autenticado, de modo que en un
  ///   dispositivo compartido cada preventa solo ve sus propios pedidos.
  ///   Coincide con el campo `usuario` del `PedidoResponse` del backend
  ///   (es el `nombreUsuario`/login, no el id numérico).
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
    8: [
      '''
      CREATE TABLE pedidos (
        id_local TEXT PRIMARY KEY,
        id_servidor INTEGER UNIQUE,
        id_odoo TEXT,
        numero TEXT,
        fecha INTEGER NOT NULL,
        cliente_id_local TEXT NOT NULL,
        cliente_id_servidor INTEGER,
        cliente_nombre TEXT NOT NULL,
        total_base REAL NOT NULL DEFAULT 0,
        total_iva REAL NOT NULL DEFAULT 0,
        total_re REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        estado_pedido TEXT NOT NULL
          CHECK (estado_pedido IN ('BORRADOR','CONFIRMADO','ANULADO')),
        estado_sync TEXT NOT NULL
          CHECK (estado_sync IN ('SINCRONIZADO','PENDENTE','ERRO')),
        mensaje_error TEXT,
        actualizado_en INTEGER NOT NULL,
        creado_en INTEGER NOT NULL,
        FOREIGN KEY (cliente_id_local) REFERENCES clientes(id_local)
      )
      ''',
      'CREATE INDEX idx_pedidos_cliente ON pedidos(cliente_id_local)',
      'CREATE INDEX idx_pedidos_estado_sync ON pedidos(estado_sync)',
      'CREATE INDEX idx_pedidos_fecha ON pedidos(fecha DESC)',
      '''
      CREATE TABLE lineas_pedido (
        id_local TEXT PRIMARY KEY,
        pedido_id_local TEXT NOT NULL,
        producto_id INTEGER NOT NULL,
        codigo_producto TEXT,
        descripcion TEXT NOT NULL,
        precio REAL NOT NULL,
        iva REAL NOT NULL,
        recargo_equivalencia REAL NOT NULL DEFAULT 0,
        cantidade INTEGER NOT NULL,
        subtotal REAL NOT NULL,
        FOREIGN KEY (pedido_id_local) REFERENCES pedidos(id_local) ON DELETE CASCADE
      )
      ''',
      'CREATE INDEX idx_lineas_pedido ON lineas_pedido(pedido_id_local)',
    ],
    9: [
      'ALTER TABLE pedidos ADD COLUMN usuario_login TEXT',
      'CREATE INDEX idx_pedidos_usuario ON pedidos(usuario_login)',
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
