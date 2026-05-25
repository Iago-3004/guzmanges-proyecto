import 'package:dio/dio.dart';

import '../core/network/api_client.dart';
import '../models/sesion.dart';

/// Acceso a los endpoints de autenticación de la API.
class AuthService {
  final ApiClient _apiClient;

  AuthService(this._apiClient);

  /// Inicia sesión contra POST /auth/login.
  ///
  /// Devuelve los datos de la sesión o lanza una [Exception] con un mensaje
  /// legible para mostrar al usuario.
  Future<Sesion> login(String nombreUsuario, String contrasena) async {
    try {
      final respuesta = await _apiClient.dio.post('/auth/login', data: {
        'nombreUsuario': nombreUsuario,
        'contrasena': contrasena,
      });
      return Sesion.fromJson(respuesta.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('Usuario o contraseña incorrectos');
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw Exception(
            'No se puede conectar con el servidor. Comprueba la URL y la conexión');
      }
      throw Exception(
          'Error al iniciar sesión (${e.response?.statusCode ?? 'sin respuesta'})');
    }
  }
}
