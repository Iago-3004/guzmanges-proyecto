import 'package:shared_preferences/shared_preferences.dart';

/// Almacén de la configuración de la app (datos no sensibles), como la URL del
/// servidor. Usa SharedPreferences; se borra al desinstalar la app, de modo que
/// una reinstalación vuelve a pedir la configuración inicial.
class ConfigStorage {
  static const String _claveUrlServidor = 'url_servidor';

  /// Guarda la URL del servidor.
  Future<void> guardarUrlServidor(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveUrlServidor, url);
  }

  /// Devuelve la URL del servidor guardada, o null si todavía no se configuró.
  Future<String?> leerUrlServidor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_claveUrlServidor);
  }
}
