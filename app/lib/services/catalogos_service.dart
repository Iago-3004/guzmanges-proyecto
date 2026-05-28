import 'package:dio/dio.dart';

import '../core/network/api_client.dart';
import '../models/condicion_pago.dart';
import '../models/modo_pago.dart';

/// Acceso a los endpoints de catálogos de pago de la API.
///
/// Ambos endpoints (`GET /modos-pago` y `GET /condiciones-pago`) aceptan el
/// parámetro opcional `?modificadoDesde=<ISO-8601>` para devolver solo los
/// registros modificados a partir de esa fecha (incluidos los desactivados).
/// Si no se pasa, devuelven únicamente los activos.
class CatalogosService {
  final ApiClient _apiClient;

  CatalogosService(this._apiClient);

  /// Lista de modos de pago. Si [modificadoDesde] no es null, se pide solo
  /// lo modificado a partir de esa fecha (sincronización incremental).
  Future<List<ModoPago>> listarModos({DateTime? modificadoDesde}) async {
    return _listar<ModoPago>(
      ruta: '/modos-pago',
      modificadoDesde: modificadoDesde,
      desdeJson: ModoPago.fromJson,
    );
  }

  /// Lista de condiciones de pago. Si [modificadoDesde] no es null, se pide
  /// solo lo modificado a partir de esa fecha.
  Future<List<CondicionPago>> listarCondiciones({DateTime? modificadoDesde}) async {
    return _listar<CondicionPago>(
      ruta: '/condiciones-pago',
      modificadoDesde: modificadoDesde,
      desdeJson: CondicionPago.fromJson,
    );
  }

  /// Llamada genérica que añade el filtro incremental si procede, parsea la
  /// respuesta y traduce los errores de red a [Exception] con mensaje legible.
  Future<List<T>> _listar<T>({
    required String ruta,
    required DateTime? modificadoDesde,
    required T Function(Map<String, dynamic>) desdeJson,
  }) async {
    try {
      final parametros = <String, dynamic>{};
      if (modificadoDesde != null) {
        // ISO-8601 local sin zona; el backend lo parsea como LocalDateTime.
        parametros['modificadoDesde'] = modificadoDesde.toIso8601String();
      }
      final respuesta = await _apiClient.dio.get(
        ruta,
        queryParameters: parametros.isEmpty ? null : parametros,
      );
      final lista = respuesta.data as List<dynamic>;
      return lista
          .map((e) => desdeJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('Sesión caducada');
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw Exception(
            'No se puede conectar con el servidor. Comprueba la conexión');
      }
      throw Exception(
          'Error al sincronizar $ruta (${e.response?.statusCode ?? 'sin respuesta'})');
    }
  }
}
