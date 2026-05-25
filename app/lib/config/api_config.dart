/// Valores por defecto relativos a la configuración de acceso a la API.
///
/// La URL del servidor ya no es una constante: la introduce el usuario en la
/// primera ejecución y se guarda de forma persistente (ver [ConfigStorage]).
/// Aquí solo queda un ejemplo de formato que se muestra como sugerencia en el
/// formulario de configuración inicial.
class ApiConfig {
  ApiConfig._();

  /// Ejemplo de URL mostrado en el formulario de configuración inicial.
  /// 10.0.2.2 es la dirección del localhost del PC desde el emulador de Android.
  static const String urlEjemplo = 'http://10.0.2.2:8080';
}
