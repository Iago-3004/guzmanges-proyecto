import 'package:dio/dio.dart';

import '../core/network/api_client.dart';

/// Acceso a los endpoints REST de clientes.
///
/// Devuelve los JSON tal cual los entrega la API: la conversión a la entidad
/// local [Cliente] se hace en el provider para poder enriquecerla con el
/// `id_local` (UUID) que solo conoce SQLite.
class ClientesService {
  final ApiClient _apiClient;

  ClientesService(this._apiClient);

  /// Lista de clientes. Si [modificadoDesde] no es null, se pide solo lo
  /// modificado a partir de esa fecha; entonces la respuesta incluye también
  /// los desactivados, para que la app refleje las bajas.
  Future<List<Map<String, dynamic>>> listar({DateTime? modificadoDesde}) async {
    try {
      final parametros = <String, dynamic>{};
      if (modificadoDesde != null) {
        parametros['modificadoDesde'] = modificadoDesde.toIso8601String();
      }
      final respuesta = await _apiClient.dio.get(
        '/clientes',
        queryParameters: parametros.isEmpty ? null : parametros,
      );
      final lista = respuesta.data as List<dynamic>;
      return lista.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw _traducirError(e, '/clientes');
    }
  }

  /// Recupera un cliente concreto por su id del servidor.
  Future<Map<String, dynamic>> obtenerPorId(int idServidor) async {
    try {
      final respuesta = await _apiClient.dio.get('/clientes/$idServidor');
      return respuesta.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _traducirError(e, '/clientes/$idServidor');
    }
  }

  /// Traduce un [DioException] a una [Exception] con mensaje legible para
  /// mostrar al usuario en un SnackBar.
  Exception _traducirError(DioException e, String ruta) {
    if (e.response?.statusCode == 401) {
      return Exception('Sesión caducada');
    }
    if (e.response?.statusCode == 404) {
      return Exception('Cliente no encontrado');
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return Exception(
          'No se puede conectar con el servidor. Comprueba la conexión');
    }
    return Exception(
        'Error al consultar $ruta (${e.response?.statusCode ?? 'sin respuesta'})');
  }
}
