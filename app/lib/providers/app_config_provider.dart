import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, kDebugMode, debugPrint;

import '../core/network/api_client.dart';
import '../core/storage/config_storage.dart';

/// Gestiona la configuración inicial de la app: la URL del servidor.
///
/// En la primera ejecución no hay URL guardada y se muestra el formulario de
/// configuración. Una vez guardada, la app pasa directamente al login y este
/// formulario no vuelve a mostrarse (salvo reinstalación o borrado de datos
/// desde la pantalla "Acerca de").
class AppConfigProvider extends ChangeNotifier {
  final ConfigStorage _configStorage;
  final ApiClient _apiClient;

  AppConfigProvider(this._configStorage, this._apiClient, String? urlInicial)
      : _urlServidor = urlInicial;

  String? _urlServidor;

  String? get urlServidor => _urlServidor;

  /// Indica si ya hay una URL de servidor configurada.
  bool get estaConfigurado => _urlServidor != null && _urlServidor!.isNotEmpty;

  /// Mensaje único de error de conexión. Se devuelve para cualquier fallo
  /// al validar la URL (timeout, host inalcanzable, 404, status != UP…),
  /// porque distinguir entre ellos en la UI suele confundir más que
  /// ayudar al usuario final, que en cualquier caso solo puede hacer una
  /// cosa: revisar la dirección.
  static const String _mensajeFalloConexion =
      'No se pudo conectar con el servidor';

  /// Comprueba que la URL responde con el endpoint público
  /// `/actuator/health` antes de guardarla. Si el servidor no responde, no
  /// está esa ruta, o devuelve un estado distinto a `UP`, lanza una
  /// excepción con un mensaje genérico legible para que la UI lo enseñe
  /// en un SnackBar.
  ///
  /// Pensado para el formulario inicial de configuración: evita guardar
  /// una URL que después haría fallar el login con un error críptico de
  /// red.
  Future<void> comprobarYGuardarUrl(String url) async {
    final limpia = _normalizar(url);
    final urlAnterior = _apiClient.dio.options.baseUrl;
    _apiClient.setBaseUrl(limpia);

    try {
      final respuesta = await _apiClient.dio.get<Map<String, dynamic>>(
        '/actuator/health',
        options: Options(
          // Timeouts más cortos que los normales: si el servidor no
          // responde a un endpoint trivial en 5s, mejor avisar al usuario.
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
        ),
      );
      final body = respuesta.data;
      final estado = body == null ? null : body['status'] as String?;
      if (estado != 'UP') {
        throw Exception(_mensajeFalloConexion);
      }
    } catch (e) {
      // Cualquier error de red o de respuesta se traduce al mismo mensaje
      // genérico. El detalle se conserva en los logs por si hace falta
      // depurar, pero la UI no lo ve.
      _apiClient.setBaseUrl(urlAnterior);
      if (kDebugMode) {
        debugPrint('AppConfigProvider: fallo verificando $limpia → $e');
      }
      throw Exception(_mensajeFalloConexion);
    }

    await _configStorage.guardarUrlServidor(limpia);
    _urlServidor = limpia;
    notifyListeners();
  }

  /// Borra la URL guardada. Tras esto, [estaConfigurado] vuelve a `false` y
  /// el árbol reactivo de la app redirige a la pantalla de configuración del
  /// servidor automáticamente. Lo usa el botón "Borrar todos los datos" de
  /// la pantalla "Acerca de".
  Future<void> limpiarUrl() async {
    await _configStorage.borrarUrlServidor();
    _apiClient.setBaseUrl('');
    _urlServidor = null;
    notifyListeners();
  }

  /// Quita espacios y las barras finales para dejar la URL en formato uniforme.
  String _normalizar(String url) {
    var limpia = url.trim();
    while (limpia.endsWith('/')) {
      limpia = limpia.substring(0, limpia.length - 1);
    }
    return limpia;
  }
}
