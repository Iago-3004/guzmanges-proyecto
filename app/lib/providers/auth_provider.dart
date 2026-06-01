import 'package:flutter/foundation.dart';

import '../core/storage/token_storage.dart';
import '../services/auth_service.dart';

/// Estado de la sesión del usuario.
enum EstadoAuth { desconocido, autenticado, noAutenticado }

/// Gestiona el inicio y cierre de sesión y el estado de autenticación.
class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final TokenStorage _tokenStorage;

  /// Callback que se invoca cada vez que cambia el preventa autenticado:
  /// al iniciar sesión, al cerrarla y al arrancar la app con sesión
  /// persistida. Pensado para que el [PedidosProvider] sepa qué usuario debe
  /// usar como filtro de la lista local: en un dispositivo compartido cada
  /// preventa solo ve los suyos, mientras que un ADMIN ve todos (mismo
  /// criterio que aplica el backend en `/pedidos`).
  ///
  /// Parámetros:
  /// - [login]: nombre de usuario autenticado, o null si no hay sesión.
  /// - [esAdmin]: true si el rol es ADMIN. Permite que el caller decida no
  ///   aplicar filtro en ese caso.
  final void Function(String? login, bool esAdmin)? onUsuarioActivoChanged;

  AuthProvider(this._authService, this._tokenStorage,
      {this.onUsuarioActivoChanged});

  EstadoAuth _estado = EstadoAuth.desconocido;
  String? _nombreUsuario;
  String? _rol;
  bool _cargando = false;
  String? _error;
  bool _sesionCaducada = false;
  bool _solicitarSincronizacion = false;

  EstadoAuth get estado => _estado;
  String? get nombreUsuario => _nombreUsuario;
  String? get rol => _rol;
  bool get cargando => _cargando;
  String? get error => _error;

  /// True si al arrancar se encontró una sesión guardada que ya había caducado.
  /// Sirve para avisar al usuario en el login. Se limpia al iniciar sesión.
  bool get sesionCaducada => _sesionCaducada;
  bool get esAdmin => _rol == 'ADMIN';

  /// Devuelve true si el usuario acaba de loguearse y todavía no se le ha
  /// preguntado si quiere sincronizar. Llamar a este getter consume la
  /// señal: la próxima vez devolverá false hasta el siguiente login.
  ///
  /// La pantalla principal lo usa para mostrar el diálogo de sincronización
  /// solo tras un login real, no cuando la app arranca con sesión persistida.
  bool consumirSolicitudSincronizacion() {
    if (!_solicitarSincronizacion) return false;
    _solicitarSincronizacion = false;
    return true;
  }

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
    onUsuarioActivoChanged?.call(_nombreUsuario, esAdmin);
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
      _solicitarSincronizacion = true;
      _cargando = false;
      onUsuarioActivoChanged?.call(_nombreUsuario, esAdmin);
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
    onUsuarioActivoChanged?.call(null, false);
    notifyListeners();
  }
}
