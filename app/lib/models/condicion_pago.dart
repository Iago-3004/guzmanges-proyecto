/// Condición de pago de un cliente (catálogo maestro sincronizado desde el servidor).
class CondicionPago {
  /// Identificador en la base de datos del servidor.
  final int id;

  /// Texto que se muestra al usuario (p. ej. "Pago inmediato", "30 días").
  final String descripcion;

  /// Si está activa. Las inactivas se mantienen en caché para resolver pedidos
  /// antiguos pero no aparecen en los selectores de alta de clientes.
  final bool activo;

  const CondicionPago({
    required this.id,
    required this.descripcion,
    required this.activo,
  });

  /// Construye una instancia a partir del JSON devuelto por la API.
  factory CondicionPago.fromJson(Map<String, dynamic> json) {
    return CondicionPago(
      id: json['id'] as int,
      descripcion: json['descripcion'] as String,
      activo: json['activo'] as bool,
    );
  }

  /// Construye una instancia a partir de una fila de SQLite.
  factory CondicionPago.fromMap(Map<String, Object?> map) {
    return CondicionPago(
      id: map['id'] as int,
      descripcion: map['descripcion'] as String,
      activo: (map['activo'] as int) == 1,
    );
  }

  /// Serializa la entidad para guardarla en SQLite.
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'descripcion': descripcion,
      'activo': activo ? 1 : 0,
      'actualizado_en': DateTime.now().millisecondsSinceEpoch,
    };
  }
}
