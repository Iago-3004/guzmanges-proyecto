import 'package:flutter/foundation.dart';

import '../core/storage/token_storage.dart';
import '../services/auth_service.dart';

/// Estado de la sesión del usuario.
enum EstadoAuth { desconocido, autenticado, noAutenticado }

/// Gestiona el inicio y cierre de sesión y el estado de autenticación.
class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final TokenStorage _tokenStorage;

  AuthProvider(this._authService, this._tokenStorage);

  EstadoAuth _estado = EstadoAuth.desconocido;
  String? _nombreUsuario;
  String? _rol;
  bool _cargando = false;
  String? _error;
  bool _sesionCaducada = false;

  EstadoAuth get estado => _estado;
  String? get nombreUsuario => _nombreUsuario;
  String? get rol => _rol;
  bool get cargando => _cargando;
  String? get error => _error;

  /// True si al arrancar se encontró una sesión guardada que ya había caducado.
  /// Sirve para avisar al usuario en el login. Se limpia al iniciar sesión.
  bool get sesionCaducada => _sesionCaducada;
  bool get esAdmin => _rol == 'ADMIN';

  /// Comprueba si hay una sesión guardada y todavía válida (token no caducado).
  /// Se llama al arrancar la app.
  Future<void> comprobarSesion() async {
    final token = await _tokenStorage.leerToken();
    final expira = await _tokenStorage.leerExpiraEpochMs();
    final ahora = DateTime.now().millisecondsSinceEpoch;
    if (token != null && token.isNotEmpty && expira != null && ahora < expira) {
      _nombreUsuario = await _tokenStorage.leerUsuario();
      _rol = await _tokenStorage.leerRol();
      _estado = EstadoAuth.autenticado;
    } else {
      // Si había un token pero ya había caducado, se avisará en el login
      if (token != null && token.isNotEmpty) {
        _sesionCaducada = true;
      }
      await _tokenStorage.limpiarSesion();
      _estado = EstadoAuth.noAutenticado;
    }
    notifyListeners();
  }

  /// Inicia sesión. Devuelve true si fue correcto; si falla, deja el mensaje en [error].
  Future<bool> login(String nombreUsuario, String contrasena) async {
    _cargando = true;
    _error = null;
    _sesionCaducada = false;
    notifyListeners();
    try {
      final sesion = await _authService.login(nombreUsuario, contrasena);
      final expiraEpoch =
          DateTime.now().millisecondsSinceEpoch + sesion.expiraEnMs;
      await _tokenStorage.guardarSesion(
        token: sesion.token,
        expiraEpochMs: expiraEpoch,
        nombreUsuario: sesion.nombreUsuario,
        rol: sesion.rol,
      );
      _nombreUsuario = sesion.nombreUsuario;
      _rol = sesion.rol;
      _estado = EstadoAuth.autenticado;
      _cargando = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _cargando = false;
      notifyListeners();
      return false;
    }
  }

  /// Cierra la sesión y vuelve al login.
  Future<void> logout() async {
    await _tokenStorage.limpiarSesion();
    _nombreUsuario = null;
    _rol = null;
    _sesionCaducada = false;
    _estado = EstadoAuth.noAutenticado;
    notifyListeners();
  }
}
