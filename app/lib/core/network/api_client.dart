import 'package:dio/dio.dart';

import '../storage/token_storage.dart';

/// Cliente HTTP central (Dio) para comunicarse con la API.
///
/// La URL base se establece en tiempo de ejecución ([setBaseUrl]) a partir de la
/// que el usuario configura en la primera ejecución, de modo que no haya que
/// recompilar para cambiar de servidor. Un interceptor añade el token JWT a cada
/// petición cuando hay una sesión iniciada.
class ApiClient {
  final Dio dio;
  final TokenStorage _tokenStorage;

  ApiClient(this._tokenStorage)
      : dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          contentType: 'application/json',
        )) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _tokenStorage.leerToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  /// Establece (o actualiza) la URL base del servidor.
  void setBaseUrl(String url) {
    dio.options.baseUrl = url;
  }
}
