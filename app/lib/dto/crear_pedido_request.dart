/// DTO que se envía a `POST /pedidos`.
///
/// No mapea uno a uno la entidad local: el backend espera el id del cliente
/// en servidor (no el UUID local), y por línea solo necesita un subconjunto
/// (sin id_local, sin descripción ni código denormalizados). La resolución
/// del `clienteId` desde el `clienteIdLocal` la hace el sync service antes
/// de construir este DTO.
class CrearPedidoRequest {
  /// Id del cliente en el servidor. Si el cliente todavía no se sincronizó
  /// (UUID local sin id de servidor), el envío del pedido se pospone hasta
  /// que el cliente esté arriba — este DTO no se construye en ese caso.
  final int clienteId;

  /// Líneas a crear. Debe haber al menos una (la API lo valida).
  final List<CrearLineaRequest> lineas;

  const CrearPedidoRequest({
    required this.clienteId,
    required this.lineas,
  });

  Map<String, dynamic> toJson() {
    return {
      'clienteId': clienteId,
      'lineas': lineas.map((l) => l.toJson()).toList(),
    };
  }
}

/// Una línea dentro del [CrearPedidoRequest].
///
/// Los campos `precio`, `iva` y `recargoEquivalencia` son opcionales: si se
/// omiten, el backend los toma del producto y de la posición fiscal del
/// cliente. Desde la app los enviamos siempre para que el cálculo provisional
/// del backend coincida exactamente con el que ya hizo la app y no haya
/// sorpresas en los totales antes de la confirmación de Odoo.
class CrearLineaRequest {
  final int productoId;
  final int cantidade;
  final double? precio;
  final double? iva;
  final double? recargoEquivalencia;

  const CrearLineaRequest({
    required this.productoId,
    required this.cantidade,
    this.precio,
    this.iva,
    this.recargoEquivalencia,
  });

  Map<String, dynamic> toJson() {
    final mapa = <String, dynamic>{
      'productoId': productoId,
      'cantidade': cantidade,
    };
    if (precio != null) mapa['precio'] = precio;
    if (iva != null) mapa['iva'] = iva;
    if (recargoEquivalencia != null) {
      mapa['recargoEquivalencia'] = recargoEquivalencia;
    }
    return mapa;
  }
}
