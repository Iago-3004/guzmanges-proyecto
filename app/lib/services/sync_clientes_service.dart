import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/db/dao/clientes_dao.dart';
import '../core/network/api_client.dart';
import '../models/cliente.dart';

/// Resultado del envío de clientes pendientes al servidor.
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

  /// Itera los clientes en estado PENDENTE o ERRO y los envía uno por uno a
  /// `POST /clientes`. Si el cliente lleva [Cliente.forzarEnvio] activo, se
  /// añade `?forzarAlta=true` para que el servidor no rechace por duplicado.
  Future<ResultadoEnvioPendientes> enviarPendientes() async {
    final pendientes = await _dao.listarPendientesDeEnvio();

    int sincronizados = 0;
    int conError = 0;
    bool sesionCaducada = false;

    for (final cliente in pendientes) {
      try {
        final body = _aRequestJson(cliente);
        final respuesta = await _apiClient.dio.post(
          '/clientes',
          data: body,
          queryParameters:
              cliente.forzarEnvio ? {'forzarAlta': true} : null,
        );

        final json = respuesta.data as Map<String, dynamic>;
        await _dao.marcarSincronizado(
          idLocal: cliente.idLocal,
          idServidor: json['id'] as int,
          idOdoo: json['idOdoo'] as String?,
        );
        sincronizados++;
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          // La sesión caducó: cortamos el procesamiento sin marcar errores
          // para que los clientes vuelvan a intentarse cuando el usuario
          // se reautentique.
          sesionCaducada = true;
          break;
        }
        if (e.response?.statusCode == 409) {
          // CIF duplicado: guardamos las coincidencias devueltas por el
          // backend para poder mostrarlas más tarde y dejar al usuario
          // decidir si forzar el alta.
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
          conError++;
        } else {
          await _dao.marcarError(
            idLocal: cliente.idLocal,
            mensaje: _mensajeErrorRed(e),
          );
          conError++;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('SyncClientesService: error inesperado: $e');
        await _dao.marcarError(
          idLocal: cliente.idLocal,
          mensaje: 'Error inesperado: $e',
        );
        conError++;
      }
    }

    return ResultadoEnvioPendientes(
      sincronizados: sincronizados,
      conError: conError,
      sesionCaducada: sesionCaducada,
    );
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
