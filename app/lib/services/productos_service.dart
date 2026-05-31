import 'package:dio/dio.dart';

import '../core/network/api_client.dart';
import '../models/producto.dart';

/// Acceso al endpoint REST de productos de la API.
///
/// El endpoint admite el parámetro opcional `?modificadoDesde=<ISO-8601>`
/// para sincronización incremental: cuando se pasa, el servidor devuelve solo
/// los productos modificados a partir de esa fecha (incluyendo los archivados,
/// para que la app reflexe las bajas).
class ProductosService {
  final ApiClient _apiClient;

  ProductosService(this._apiClient);

  /// Lista de productos. Si [modificadoDesde] no es null, se piden solo los
  /// modificados a partir de esa fecha; si es null, se descarga el catálogo
  /// completo (lo habitual solo en la primera sincronización).
  Future<List<Producto>> listar({DateTime? modificadoDesde}) async {
    try {
      final parametros = <String, dynamic>{};
      if (modificadoDesde != null) {
        // ISO-8601 local sin zona; el backend lo parsea como LocalDateTime.
        parametros['modificadoDesde'] = modificadoDesde.toIso8601String();
      }
      final respuesta = await _apiClient.dio.get(
        '/productos',
        queryParameters: parametros.isEmpty ? null : parametros,
      );
      final lista = respuesta.data as List<dynamic>;
      return lista
          .map((e) => Producto.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw _traducirError(e, '/productos');
    }
  }

  /// Recupera un producto concreto por su id del servidor.
  Future<Producto> obtenerPorId(int id) async {
    try {
      final respuesta = await _apiClient.dio.get('/productos/$id');
      return Producto.fromJson(respuesta.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _traducirError(e, '/productos/$id');
    }
  }

  /// Traduce un [DioException] a una [Exception] con mensaje legible.
  Exception _traducirError(DioException e, String ruta) {
    if (e.response?.statusCode == 401) {
      return Exception('Sesión caducada');
    }
    if (e.response?.statusCode == 404) {
      return Exception('Producto no encontrado');
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
