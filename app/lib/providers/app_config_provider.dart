import 'package:flutter/foundation.dart';

import '../core/network/api_client.dart';
import '../core/storage/config_storage.dart';

/// Gestiona la configuración inicial de la app: la URL del servidor.
///
/// En la primera ejecución no hay URL guardada y se muestra el formulario de
/// configuración. Una vez guardada, la app pasa directamente al login y este
/// formulario no vuelve a mostrarse (salvo reinstalación).
class AppConfigProvider extends ChangeNotifier {
  final ConfigStorage _configStorage;
  final ApiClient _apiClient;

  AppConfigProvider(this._configStorage, this._apiClient, String? urlInicial)
      : _urlServidor = urlInicial;

  String? _urlServidor;

  String? get urlServidor => _urlServidor;

  /// Indica si ya hay una URL de servidor configurada.
  bool get estaConfigurado => _urlServidor != null && _urlServidor!.isNotEmpty;

  /// Guarda la URL del servidor (normalizada) y la aplica al cliente HTTP.
  Future<void> guardarUrl(String url) async {
    final limpia = _normalizar(url);
    await _configStorage.guardarUrlServidor(limpia);
    _apiClient.setBaseUrl(limpia);
    _urlServidor = limpia;
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
