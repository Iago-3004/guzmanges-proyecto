/// Datos de la sesión devueltos por la API al iniciar sesión (POST /auth/login).
class Sesion {
  final String token;
  final String nombreUsuario;
  final String rol;

  /// Duración del token en milisegundos (campo "expiraEn" de la API).
  final int expiraEnMs;

  Sesion({
    required this.token,
    required this.nombreUsuario,
    required this.rol,
    required this.expiraEnMs,
  });

  factory Sesion.fromJson(Map<String, dynamic> json) {
    return Sesion(
      token: json['token'] as String,
      nombreUsuario: json['nombreUsuario'] as String,
      rol: json['rol'] as String,
      expiraEnMs: (json['expiraEn'] as num).toInt(),
    );
  }
}
