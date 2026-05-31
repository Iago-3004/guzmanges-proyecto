/// Datos del formulario de alta de un cliente.
///
/// Replica la forma del request que espera `POST /clientes` del backend,
/// para poder serializarse directamente con [toJson] al enviarse a la API.
class CrearClienteRequest {
  final String nombreComercial;
  final String razonSocial;
  final String cif;

  final String? direccion;
  final String? localidad;
  final String? codigoPostal;
  final String? provincia;
  final String? telefono;
  final String? movil;
  final String? email;

  final int? modoPagoId;
  final int? condicionPagoId;

  const CrearClienteRequest({
    required this.nombreComercial,
    required this.razonSocial,
    required this.cif,
    this.direccion,
    this.localidad,
    this.codigoPostal,
    this.provincia,
    this.telefono,
    this.movil,
    this.email,
    this.modoPagoId,
    this.condicionPagoId,
  });

  /// Serializa el request en la forma que espera `POST /clientes`. Los
  /// campos opcionales nulos se envían como `null`.
  Map<String, dynamic> toJson() {
    return {
      'nombreComercial': nombreComercial,
      'razonSocial': razonSocial,
      'cif': cif,
      'direccion': direccion,
      'localidad': localidad,
      'codigoPostal': codigoPostal,
      'provincia': provincia,
      'telefono': telefono,
      'movil': movil,
      'email': email,
      'modoPagoId': modoPagoId,
      'condicionPagoId': condicionPagoId,
    };
  }
}
