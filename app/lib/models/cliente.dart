/// Estado de sincronización de un cliente con el servidor.
///
/// El nombre textual ([nombreBackend]) es el que se intercambia con el
/// backend y se guarda en SQLite; el identificador Dart es independiente
/// para poder mantenerlo en minúscula CamelCase.
enum EstadoSync {
  sincronizado('SINCRONIZADO'),
  pendente('PENDENTE'),
  erro('ERRO');

  /// Valor textual del enum tal y como lo usa el backend y SQLite.
  final String nombreBackend;

  const EstadoSync(this.nombreBackend);

  /// Convierte el valor textual del backend al enum correspondiente.
  /// Si el valor no se reconoce devuelve [sincronizado] como fallback
  /// defensivo (preferimos mostrar el registro a ocultarlo o crashear).
  static EstadoSync desdeBackend(String? nombre) {
    if (nombre == null) return EstadoSync.sincronizado;
    return EstadoSync.values.firstWhere(
      (e) => e.nombreBackend == nombre,
      orElse: () => EstadoSync.sincronizado,
    );
  }
}

/// Cliente tal como se guarda en SQLite, ya provenga del servidor o se
/// haya creado localmente.
///
/// Mantiene una identidad dual: [idLocal] es un UUID generado en el móvil
/// y siempre presente; [idServidor] llega del backend, y es null mientras
/// el cliente esté pendiente de subir.
class Cliente {
  final String idLocal;
  final int? idServidor;
  final String? idOdoo;

  final String nombreComercial;
  final String? razonSocial;
  final String? cif;
  final String? direccion;
  final String? localidad;
  final String? codigoPostal;
  final String? provincia;
  final String? telefono;
  final String? movil;
  final String? email;

  /// FK al modo de pago en el servidor. La descripción se guarda
  /// denormalizada para poder pintar el listado sin un JOIN extra.
  final int? modoPagoId;
  final String? modoPagoDescripcion;

  final int? condicionPagoId;
  final String? condicionPagoDescripcion;

  /// Nombre del comercial (preventa) asignado al cliente. Solo informativo.
  final String? comercial;

  final bool activo;
  final EstadoSync estadoSync;

  /// Mensaje legible del último error al intentar sincronizar, si lo hubo.
  final String? mensajeError;

  /// JSON con la lista de coincidencias devueltas en un 409 (CIF duplicado).
  /// Permite reabrir el diálogo de confirmación desde la pantalla de estado.
  final String? coincidencias409;

  final DateTime actualizadoEn;
  final DateTime creadoEn;

  const Cliente({
    required this.idLocal,
    this.idServidor,
    this.idOdoo,
    required this.nombreComercial,
    this.razonSocial,
    this.cif,
    this.direccion,
    this.localidad,
    this.codigoPostal,
    this.provincia,
    this.telefono,
    this.movil,
    this.email,
    this.modoPagoId,
    this.modoPagoDescripcion,
    this.condicionPagoId,
    this.condicionPagoDescripcion,
    this.comercial,
    required this.activo,
    required this.estadoSync,
    this.mensajeError,
    this.coincidencias409,
    required this.actualizadoEn,
    required this.creadoEn,
  });

  /// Construye un cliente a partir del JSON devuelto por la API.
  ///
  /// El [idLocal] no viene en el JSON: lo aporta quien llame, bien con el
  /// UUID que ya tenía la fila local equivalente, bien con uno nuevo si es
  /// la primera vez que se ve el cliente.
  factory Cliente.desdeServidor(
    Map<String, dynamic> json, {
    required String idLocal,
    DateTime? creadoEn,
  }) {
    final ahora = DateTime.now();
    final modoPago = json['modoPago'] as Map<String, dynamic>?;
    final condicionPago = json['condicionPago'] as Map<String, dynamic>?;
    return Cliente(
      idLocal: idLocal,
      idServidor: json['id'] as int?,
      idOdoo: json['idOdoo'] as String?,
      nombreComercial: json['nombreComercial'] as String,
      razonSocial: json['razonSocial'] as String?,
      cif: json['cif'] as String?,
      direccion: json['direccion'] as String?,
      localidad: json['localidad'] as String?,
      codigoPostal: json['codigoPostal'] as String?,
      provincia: json['provincia'] as String?,
      telefono: json['telefono'] as String?,
      movil: json['movil'] as String?,
      email: json['email'] as String?,
      modoPagoId: modoPago?['id'] as int?,
      modoPagoDescripcion: modoPago?['descripcion'] as String?,
      condicionPagoId: condicionPago?['id'] as int?,
      condicionPagoDescripcion: condicionPago?['descripcion'] as String?,
      comercial: json['comercial'] as String?,
      activo: (json['activo'] as bool?) ?? true,
      estadoSync: EstadoSync.desdeBackend(json['estadoSync'] as String?),
      mensajeError: null,
      coincidencias409: null,
      actualizadoEn: ahora,
      creadoEn: creadoEn ?? ahora,
    );
  }

  /// Reconstruye el cliente desde una fila de SQLite.
  factory Cliente.fromMap(Map<String, Object?> map) {
    return Cliente(
      idLocal: map['id_local'] as String,
      idServidor: map['id_servidor'] as int?,
      idOdoo: map['id_odoo'] as String?,
      nombreComercial: map['nombre_comercial'] as String,
      razonSocial: map['razon_social'] as String?,
      cif: map['cif'] as String?,
      direccion: map['direccion'] as String?,
      localidad: map['localidad'] as String?,
      codigoPostal: map['codigo_postal'] as String?,
      provincia: map['provincia'] as String?,
      telefono: map['telefono'] as String?,
      movil: map['movil'] as String?,
      email: map['email'] as String?,
      modoPagoId: map['modo_pago_id'] as int?,
      modoPagoDescripcion: map['modo_pago_descripcion'] as String?,
      condicionPagoId: map['condicion_pago_id'] as int?,
      condicionPagoDescripcion: map['condicion_pago_descripcion'] as String?,
      comercial: map['comercial'] as String?,
      activo: (map['activo'] as int) == 1,
      estadoSync: EstadoSync.desdeBackend(map['estado_sync'] as String?),
      mensajeError: map['mensaje_error'] as String?,
      coincidencias409: map['coincidencias_409'] as String?,
      actualizadoEn:
          DateTime.fromMillisecondsSinceEpoch(map['actualizado_en'] as int),
      creadoEn: DateTime.fromMillisecondsSinceEpoch(map['creado_en'] as int),
    );
  }

  /// Serializa el cliente para guardar en SQLite.
  Map<String, Object?> toMap() {
    return {
      'id_local': idLocal,
      'id_servidor': idServidor,
      'id_odoo': idOdoo,
      'nombre_comercial': nombreComercial,
      'razon_social': razonSocial,
      'cif': cif,
      'direccion': direccion,
      'localidad': localidad,
      'codigo_postal': codigoPostal,
      'provincia': provincia,
      'telefono': telefono,
      'movil': movil,
      'email': email,
      'modo_pago_id': modoPagoId,
      'modo_pago_descripcion': modoPagoDescripcion,
      'condicion_pago_id': condicionPagoId,
      'condicion_pago_descripcion': condicionPagoDescripcion,
      'comercial': comercial,
      'activo': activo ? 1 : 0,
      'estado_sync': estadoSync.nombreBackend,
      'mensaje_error': mensajeError,
      'coincidencias_409': coincidencias409,
      'actualizado_en': actualizadoEn.millisecondsSinceEpoch,
      'creado_en': creadoEn.millisecondsSinceEpoch,
    };
  }
}
