/// Modo de pago de un cliente (catálogo maestro sincronizado desde el servidor).
class ModoPago {
  /// Identificador en la base de datos del servidor.
  final int id;

  /// Texto que se muestra al usuario (p. ej. "Efectivo", "Transferencia").
  final String descripcion;

  /// Si está activo. Los inactivos se mantienen en caché para resolver pedidos
  /// antiguos pero no aparecen en los selectores de alta de clientes.
  final bool activo;

  const ModoPago({
    required this.id,
    required this.descripcion,
    required this.activo,
  });

  /// Construye una instancia a partir del JSON devuelto por la API.
  factory ModoPago.fromJson(Map<String, dynamic> json) {
    return ModoPago(
      id: json['id'] as int,
      descripcion: json['descripcion'] as String,
      activo: json['activo'] as bool,
    );
  }

  /// Construye una instancia a partir de una fila de SQLite. En SQLite los
  /// booleanos se guardan como `INTEGER` (0/1).
  factory ModoPago.fromMap(Map<String, Object?> map) {
    return ModoPago(
      id: map['id'] as int,
      descripcion: map['descripcion'] as String,
      activo: (map['activo'] as int) == 1,
    );
  }

  /// Serializa la entidad para guardarla en SQLite. `actualizado_en` se rellena
  /// con el instante actual para poder ordenar por recencia si hace falta.
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'descripcion': descripcion,
      'activo': activo ? 1 : 0,
      'actualizado_en': DateTime.now().millisecondsSinceEpoch,
    };
  }
}
