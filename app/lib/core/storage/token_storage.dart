import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Almacén seguro del token JWT y de los datos básicos de la sesión.
/// El token se guarda cifrado mediante flutter_secure_storage.
class TokenStorage {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _claveToken = 'jwt_token';
  static const String _claveExpira = 'jwt_expira_epoch_ms';
  static const String _claveUsuario = 'usuario';
  static const String _claveRol = 'rol';

  /// Guarda el token y los datos de la sesión.
  ///
  /// @param expiraEpochMs instante de caducidad del token en epoch (ms)
  Future<void> guardarSesion({
    required String token,
    required int expiraEpochMs,
    required String nombreUsuario,
    required String rol,
  }) async {
    await _storage.write(key: _claveToken, value: token);
    await _storage.write(key: _claveExpira, value: expiraEpochMs.toString());
    await _storage.write(key: _claveUsuario, value: nombreUsuario);
    await _storage.write(key: _claveRol, value: rol);
  }

  Future<String?> leerToken() => _storage.read(key: _claveToken);

  Future<int?> leerExpiraEpochMs() async {
    final valor = await _storage.read(key: _claveExpira);
    return valor == null ? null : int.tryParse(valor);
  }

  Future<String?> leerUsuario() => _storage.read(key: _claveUsuario);

  Future<String?> leerRol() => _storage.read(key: _claveRol);

  /// Borra los datos de la sesión (logout). No afecta a la configuración de la app.
  Future<void> limpiarSesion() async {
    await _storage.delete(key: _claveToken);
    await _storage.delete(key: _claveExpira);
    await _storage.delete(key: _claveUsuario);
    await _storage.delete(key: _claveRol);
  }
}
