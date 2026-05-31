import 'package:dio/dio.dart';

import '../core/network/api_client.dart';
import '../dto/crear_pedido_request.dart';

/// Acceso a los endpoints REST de pedidos.
///
/// Devuelve los JSON tal cual los entrega la API: la conversión a la entidad
/// local [Pedido] se hace en el provider / sync service para poder enriquecerla
/// con los UUIDs locales que solo conoce SQLite.
class PedidosService {
  final ApiClient _apiClient;

  PedidosService(this._apiClient);

  /// Lista de pedidos visibles para el usuario autenticado. Si
  /// [modificadoDesde] no es null, pide solo los modificados desde esa fecha
  /// (sincronización incremental).
  Future<List<Map<String, dynamic>>> listar(
      {DateTime? modificadoDesde}) async {
    try {
      final parametros = <String, dynamic>{};
      if (modificadoDesde != null) {
        parametros['modificadoDesde'] = modificadoDesde.toIso8601String();
      }
      final respuesta = await _apiClient.dio.get(
        '/pedidos',
        queryParameters: parametros.isEmpty ? null : parametros,
      );
      final lista = respuesta.data as List<dynamic>;
      return lista.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw _traducirError(e, '/pedidos');
    }
  }

  /// Recupera un pedido concreto por su id del servidor.
  Future<Map<String, dynamic>> obtenerPorId(int idServidor) async {
    try {
      final respuesta = await _apiClient.dio.get('/pedidos/$idServidor');
      return respuesta.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _traducirError(e, '/pedidos/$idServidor');
    }
  }

  /// Envía un pedido nuevo al servidor (`POST /pedidos`). El backend
  /// guardará el pedido, intentará subirlo a Odoo en la misma petición y
  /// devolverá la respuesta ya con los totales definitivos si lo consigue,
  /// o con los provisionales si Odoo no estuvo disponible.
  Future<Map<String, dynamic>> crear(CrearPedidoRequest request) async {
    try {
      final respuesta = await _apiClient.dio.post(
        '/pedidos',
        data: request.toJson(),
      );
      return respuesta.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _traducirError(e, '/pedidos');
    }
  }

  /// Traduce un [DioException] a una [Exception] con mensaje legible para
  /// mostrar al usuario en un SnackBar.
  Exception _traducirError(DioException e, String ruta) {
    if (e.response?.statusCode == 401) {
      return Exception('Sesión caducada');
    }
    if (e.response?.statusCode == 404) {
      return Exception('Pedido no encontrado');
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
