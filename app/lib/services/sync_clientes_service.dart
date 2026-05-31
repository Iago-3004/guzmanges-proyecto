import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/db/dao/clientes_dao.dart';
import '../core/network/api_client.dart';
import '../models/cliente.dart';

/// Resultado del envío de un único cliente al servidor.
///
/// Permite a quien llama distinguir si el cliente quedó SINCRONIZADO, en
/// ERRO (con o sin coincidencias 409), o si la sesión caducó y debe
/// pararse cualquier procesamiento posterior.
enum ResultadoEnvioUno {
  /// El servidor aceptó el alta y el cliente está SINCRONIZADO.
  sincronizado,

  /// El servidor devolvió 409: el CIF ya existe. El cliente queda en ERRO
  /// con `coincidencias_409` rellenado para poder mostrarlas más tarde.
  duplicado409,

  /// Error de red, timeout o cualquier otro fallo no clasificado. El
  /// cliente queda en ERRO con un mensaje legible.
  errorRecuperable,

  /// 401: la sesión del usuario caducó. No se ha tocado el cliente. Quien
  /// llama debe parar el procesamiento y disparar el flujo de re-login.
  sesionCaducada,
}

/// Resultado del envío de la lista completa de clientes pendientes al
/// servidor. Agrega los conteos y avisa si la sesión se ha caducado.
class ResultadoEnvioPendientes {
  /// Cuántos clientes han pasado a SINCRONIZADO.
  final int sincronizados;

  /// Cuántos han quedado en ERRO (CIF duplicado, error de servidor, etc.).
  final int conError;

  /// Si true, una respuesta 401 del servidor cortó el procesamiento (la sesión
  /// del usuario caducó). Los clientes no procesados siguen como estaban.
  final bool sesionCaducada;

  const ResultadoEnvioPendientes({
    required this.sincronizados,
    required this.conError,
    required this.sesionCaducada,
  });
}

/// Envía a la API los clientes que están pendientes de subir o que fallaron
/// en envíos anteriores. No bloquea la sincronización ante un error en una
/// fila concreta: registra el problema y sigue con el siguiente cliente.
class SyncClientesService {
  final ApiClient _apiClient;
  final ClientesDao _dao;

  SyncClientesService(this._apiClient, this._dao);

  /// Itera los clientes que aún no se han subido al servidor y los envía
  /// uno por uno a `POST /clientes`. Si la sesión caduca (401), se corta
  /// el procesamiento dejando intactos los clientes que faltan.
  Future<ResultadoEnvioPendientes> enviarPendientes() async {
    final pendientes = await _dao.listarPendientesDeEnvio();

    int sincronizados = 0;
    int conError = 0;
    bool sesionCaducada = false;

    for (final cliente in pendientes) {
      final resultado = await reenviarUno(
        cliente,
        forzarAlta: cliente.forzarEnvio,
      );
      switch (resultado) {
        case ResultadoEnvioUno.sincronizado:
          sincronizados++;
        case ResultadoEnvioUno.duplicado409:
        case ResultadoEnvioUno.errorRecuperable:
          conError++;
        case ResultadoEnvioUno.sesionCaducada:
          sesionCaducada = true;
      }
      if (sesionCaducada) break;
    }

    return ResultadoEnvioPendientes(
      sincronizados: sincronizados,
      conError: conError,
      sesionCaducada: sesionCaducada,
    );
  }

  /// Envía un único cliente al servidor con `POST /clientes`. Si
  /// [forzarAlta] es true, añade `?forzarAlta=true` para que la API no
  /// rechace por CIF duplicado.
  ///
  /// Actualiza directamente la fila en SQLite con el resultado:
  /// - 200/201 → SINCRONIZADO (con `id_servidor` y `id_odoo`).
  /// - 409 → ERRO con `coincidencias_409` rellenado.
  /// - 401 → no toca nada (la sesión caducó, la próxima sincronización
  ///   tras reautenticarse volverá a intentarlo).
  /// - Otros → ERRO con un mensaje legible.
  Future<ResultadoEnvioUno> reenviarUno(
    Cliente cliente, {
    bool forzarAlta = false,
  }) async {
    try {
      final body = _aRequestJson(cliente);
      final respuesta = await _apiClient.dio.post(
        '/clientes',
        data: body,
        queryParameters: forzarAlta ? {'forzarAlta': true} : null,
      );

      final json = respuesta.data as Map<String, dynamic>;
      await _dao.marcarSincronizado(
        idLocal: cliente.idLocal,
        idServidor: json['id'] as int,
        idOdoo: json['idOdoo'] as String?,
      );
      return ResultadoEnvioUno.sincronizado;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return ResultadoEnvioUno.sesionCaducada;
      }
      if (e.response?.statusCode == 409) {
        final body = e.response?.data;
        String? coincidencias;
        if (body is Map<String, dynamic> && body['clientes'] is List) {
          coincidencias = jsonEncode(body['clientes']);
        }
        await _dao.marcarError(
          idLocal: cliente.idLocal,
          mensaje: 'Posible duplicado en el servidor',
          coincidencias409: coincidencias,
        );
        return ResultadoEnvioUno.duplicado409;
      }
      await _dao.marcarError(
        idLocal: cliente.idLocal,
        mensaje: _mensajeErrorRed(e),
      );
      return ResultadoEnvioUno.errorRecuperable;
    } catch (e) {
      if (kDebugMode) debugPrint('SyncClientesService: error inesperado: $e');
      await _dao.marcarError(
        idLocal: cliente.idLocal,
        mensaje: 'Error inesperado: $e',
      );
      return ResultadoEnvioUno.errorRecuperable;
    }
  }

  /// Construye el body JSON que espera `POST /clientes` a partir de un
  /// cliente local. Los campos vacíos se mandan como null.
  Map<String, dynamic> _aRequestJson(Cliente c) {
    return {
      'nombreComercial': c.nombreComercial,
      'razonSocial': c.razonSocial,
      'cif': c.cif,
      'direccion': c.direccion,
      'localidad': c.localidad,
      'codigoPostal': c.codigoPostal,
      'provincia': c.provincia,
      'telefono': c.telefono,
      'movil': c.movil,
      'email': c.email,
      'modoPagoId': c.modoPagoId,
      'condicionPagoId': c.condicionPagoId,
    };
  }

  /// Traduce los errores de red de Dio a un mensaje legible para guardar
  /// en la fila del cliente.
  String _mensajeErrorRed(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return 'No hay conexión con el servidor';
    }
    final codigo = e.response?.statusCode;
    if (codigo != null) {
      return 'Error del servidor ($codigo)';
    }
    return 'Error de red';
  }
}
