/// Producto del catálogo, sincronizado desde el servidor.
///
/// Los productos son de solo lectura: se gestionan en Odoo, se importan al
/// backend y la app los cachea en local para que el comercial pueda crear
/// pedidos offline. No hay alta ni edición desde la app, por eso la identidad
/// es directamente el id del servidor (sin UUID local como en clientes o
/// pedidos).
class Producto {
  /// Identificador en la base de datos del servidor. Coincide con el de la
  /// tabla del backend y se usa como clave también en SQLite.
  final int id;

  /// Id del producto en Odoo. Solo informativo; la app no lo usa para hacer
  /// peticiones — Odoo es invisible para ella.
  final String? idOdoo;

  /// Código interno o SKU del producto (p. ej. "REF-001").
  final String? referencia;

  /// Texto principal a mostrar al usuario.
  final String descripcion;

  final String? codigoBarras;
  final String? tipoProducto;

  /// Stock disponible en el momento de la última sincronización. Se muestra
  /// orientativo: si dos comerciales venden offline al mismo tiempo, el stock
  /// real lo decide Odoo al confirmar los pedidos.
  final int? stock;

  /// Precio de venta (sin IVA). Si en Odoo está sin precio asignado puede
  /// venir como null.
  final double? precioVenta;

  /// IVA por defecto en porcentaje (21.0, 10.0, 4.0, ...). Lo arrastra el
  /// producto desde Odoo (`taxes_id`). Cuando se construye una línea de
  /// pedido la app autocompleta el IVA con este valor; el cálculo final lo
  /// recalcula Odoo al confirmar aplicando la posición fiscal del cliente.
  final double? iva;

  final String? observaciones;

  /// Marca temporal del momento en que la fila se actualizó en local. Solo
  /// informativa; el filtro incremental con el servidor se hace por la
  /// marca global de sincronización, no por esta columna.
  final DateTime actualizadoEn;

  const Producto({
    required this.id,
    this.idOdoo,
    this.referencia,
    required this.descripcion,
    this.codigoBarras,
    this.tipoProducto,
    this.stock,
    this.precioVenta,
    this.iva,
    this.observaciones,
    required this.actualizadoEn,
  });

  /// Construye una instancia a partir del JSON devuelto por `GET /productos`.
  /// Los campos numéricos del backend (BigDecimal) llegan como num en Dart;
  /// se convierten a double con `toDouble()` para evitar problemas si Odoo
  /// devuelve un entero (p. ej. precio 10 vs 10.00).
  factory Producto.fromJson(Map<String, dynamic> json) {
    final precio = json['precioVenta'];
    final ivaJson = json['iva'];
    return Producto(
      id: json['id'] as int,
      idOdoo: json['idOdoo'] as String?,
      referencia: json['referencia'] as String?,
      descripcion: json['descripcion'] as String,
      codigoBarras: json['codigoBarras'] as String?,
      tipoProducto: json['tipoProduto'] as String?,
      stock: json['stock'] as int?,
      precioVenta: precio == null ? null : (precio as num).toDouble(),
      iva: ivaJson == null ? null : (ivaJson as num).toDouble(),
      observaciones: json['observaciones'] as String?,
      actualizadoEn: DateTime.now(),
    );
  }

  /// Reconstruye el producto desde una fila de SQLite.
  factory Producto.fromMap(Map<String, Object?> map) {
    return Producto(
      id: map['id'] as int,
      idOdoo: map['id_odoo'] as String?,
      referencia: map['referencia'] as String?,
      descripcion: map['descripcion'] as String,
      codigoBarras: map['codigo_barras'] as String?,
      tipoProducto: map['tipo_producto'] as String?,
      stock: map['stock'] as int?,
      precioVenta: (map['precio_venta'] as num?)?.toDouble(),
      iva: (map['iva'] as num?)?.toDouble(),
      observaciones: map['observaciones'] as String?,
      actualizadoEn:
          DateTime.fromMillisecondsSinceEpoch(map['actualizado_en'] as int),
    );
  }

  /// Serializa el producto para guardarlo en SQLite.
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'id_odoo': idOdoo,
      'referencia': referencia,
      'descripcion': descripcion,
      'codigo_barras': codigoBarras,
      'tipo_producto': tipoProducto,
      'stock': stock,
      'precio_venta': precioVenta,
      'iva': iva,
      'observaciones': observaciones,
      'actualizado_en': actualizadoEn.millisecondsSinceEpoch,
    };
  }
}
