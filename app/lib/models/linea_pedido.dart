/// Línea de un pedido guardada en SQLite.
///
/// Cada línea apunta a un producto del catálogo por su id del servidor: los
/// productos son de solo lectura, siempre tienen `id_servidor`, así que no
/// hace falta identidad dual aquí. El [idLocal] (UUID) sí se mantiene para
/// poder identificar la línea de forma estable aunque el pedido aún no esté
/// sincronizado y para sobrevivir a reordenaciones en la UI.
///
/// Los importes se guardan denormalizados desde el catálogo: descripción,
/// precio, IVA, recargo y subtotal son los del momento de la captura. Si
/// luego cambia el catálogo o Odoo aplica la posición fiscal, el subtotal de
/// la línea sigue siendo el provisional — los totales definitivos se reflejan
/// en la cabecera del pedido tras la confirmación.
class LineaPedido {
  /// UUID v4 generado en la app. Estable durante toda la vida de la línea.
  final String idLocal;

  /// UUID del pedido al que pertenece la línea.
  final String pedidoIdLocal;

  /// Id del producto en el servidor. Como los productos son read-only y
  /// siempre están sincronizados, este id es válido desde el momento del alta.
  final int productoId;

  /// Referencia/SKU del producto al construir la línea. Denormalizado para
  /// pintar la lista sin tener que volver a buscar el producto.
  final String? codigoProducto;

  /// Descripción del producto al construir la línea (denormalizada por el
  /// mismo motivo que [codigoProducto]).
  final String descripcion;

  /// Precio unitario sin impuestos, en euros.
  final double precio;

  /// IVA en porcentaje (21.0, 10.0, 4.0...).
  final double iva;

  /// Recargo de equivalencia en porcentaje (5.2, 1.4, 0.5 o 0.0).
  /// Provisional: si el cliente no aplica RE, Odoo lo ignorará al confirmar.
  final double recargoEquivalencia;

  /// Unidades vendidas. Entero (el backend usa `Integer` para `cantidade`).
  final int cantidade;

  /// Subtotal con impuestos: `precio * cantidade * (1 + iva/100 + re/100)`.
  /// Se guarda calculado para no recomputarlo a cada pintada de la lista.
  final double subtotal;

  const LineaPedido({
    required this.idLocal,
    required this.pedidoIdLocal,
    required this.productoId,
    this.codigoProducto,
    required this.descripcion,
    required this.precio,
    required this.iva,
    this.recargoEquivalencia = 0.0,
    required this.cantidade,
    required this.subtotal,
  });

  /// Construye una línea a partir del JSON de un `PedidoResponse.lineas[i]`
  /// devuelto por la API. [pedidoIdLocal] e [idLocal] los aporta quien llama
  /// (en la práctica, el provider que está reconstruyendo el pedido y conoce
  /// los UUIDs locales que deben reutilizarse).
  factory LineaPedido.desdeServidor(
    Map<String, dynamic> json, {
    required String idLocal,
    required String pedidoIdLocal,
  }) {
    return LineaPedido(
      idLocal: idLocal,
      pedidoIdLocal: pedidoIdLocal,
      productoId: json['productoId'] as int,
      codigoProducto: json['codigoProducto'] as String?,
      descripcion: json['descripcion'] as String,
      precio: (json['precio'] as num).toDouble(),
      iva: (json['iva'] as num).toDouble(),
      recargoEquivalencia:
          (json['recargoEquivalencia'] as num?)?.toDouble() ?? 0.0,
      cantidade: json['cantidade'] as int,
      subtotal: (json['subtotal'] as num).toDouble(),
    );
  }

  /// Reconstruye la línea desde una fila de SQLite.
  factory LineaPedido.fromMap(Map<String, Object?> map) {
    return LineaPedido(
      idLocal: map['id_local'] as String,
      pedidoIdLocal: map['pedido_id_local'] as String,
      productoId: map['producto_id'] as int,
      codigoProducto: map['codigo_producto'] as String?,
      descripcion: map['descripcion'] as String,
      precio: (map['precio'] as num).toDouble(),
      iva: (map['iva'] as num).toDouble(),
      recargoEquivalencia:
          ((map['recargo_equivalencia'] as num?) ?? 0).toDouble(),
      cantidade: map['cantidade'] as int,
      subtotal: (map['subtotal'] as num).toDouble(),
    );
  }

  /// Serializa la línea para guardarla en SQLite.
  Map<String, Object?> toMap() {
    return {
      'id_local': idLocal,
      'pedido_id_local': pedidoIdLocal,
      'producto_id': productoId,
      'codigo_producto': codigoProducto,
      'descripcion': descripcion,
      'precio': precio,
      'iva': iva,
      'recargo_equivalencia': recargoEquivalencia,
      'cantidade': cantidade,
      'subtotal': subtotal,
    };
  }
}
