import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/db/dao/clientes_dao.dart';
import '../core/db/dao/pedidos_dao.dart';
import '../core/network/api_client.dart';
import '../dto/crear_pedido_request.dart';
import '../models/pedido.dart';

/// Resultado del envío de un único pedido al servidor.
///
/// Distingue el caso "esperando cliente" del resto de errores porque la UI
/// lo presenta diferente: no es un error de la app, es una dependencia que
/// se resolverá sola en cuanto el cliente se sincronice.
enum ResultadoEnvioPedido {
  /// El servidor aceptó el alta. El pedido queda SINCRONIZADO con su
  /// `id_servidor`, `id_odoo` (si Odoo respondió) y totales definitivos.
  sincronizado,

  /// El pedido apunta a un cliente que aún no tiene id de servidor. No se
  /// llega a llamar a la API: el pedido queda en ERRO con el mensaje
  /// "Esperando a que se sincronice el cliente".
  esperandoCliente,

  /// Error de red, timeout, 4xx no contemplado, etc. El pedido queda en
  /// ERRO con un mensaje legible.
  errorRecuperable,

  /// 401: la sesión caducó. No se ha tocado el pedido. Quien llame debe
  /// cortar el procesamiento y disparar el flujo de re-login.
  sesionCaducada,
}

/// Resultado del envío de la lista completa de pedidos pendientes.
class ResultadoEnvioPedidos {
  /// Cuántos pedidos han pasado a SINCRONIZADO.
  final int sincronizados;

  /// Cuántos han quedado en ERRO (esperando cliente o error real).
  final int conError;

  /// Cuántos quedaron concretamente en "esperando cliente". Se cuentan
  /// también dentro de [conError]; este subcontador es para que la UI
  /// pueda explicar el motivo principal de los fallos.
  final int esperandoCliente;

  /// Si true, una respuesta 401 cortó el procesamiento. Los pedidos no
  /// procesados siguen como estaban.
  final bool sesionCaducada;

  const ResultadoEnvioPedidos({
    required this.sincronizados,
    required this.conError,
    required this.esperandoCliente,
    required this.sesionCaducada,
  });
}

/// Envía a la API los pedidos pendientes de subir y resuelve la dependencia
/// con clientes pendientes: si el cliente del pedido no tiene `id_servidor`,
/// el pedido se marca como "esperando cliente" y se reintenta en la siguiente
/// vuelta (típicamente después de subir el cliente con éxito).
class SyncPedidosService {
  final ApiClient _apiClient;
  final PedidosDao _pedidosDao;
  final ClientesDao _clientesDao;

  SyncPedidosService(this._apiClient, this._pedidosDao, this._clientesDao);

  /// Itera los pedidos pendientes y los envía uno a uno. Conserva el orden
  /// FIFO de creación para que la cola sea predecible. Si la sesión caduca
  /// (401), corta sin tocar lo que queda.
  Future<ResultadoEnvioPedidos> enviarPendientes({String? usuarioLogin}) async {
    final pendientes =
        await _pedidosDao.listarPendientesDeEnvio(usuarioLogin: usuarioLogin);

    int sincronizados = 0;
    int conError = 0;
    int esperando = 0;
    bool sesionCaducada = false;

    for (final pedido in pendientes) {
      final resultado = await reenviarUno(pedido);
      switch (resultado) {
        case ResultadoEnvioPedido.sincronizado:
          sincronizados++;
        case ResultadoEnvioPedido.esperandoCliente:
          conError++;
          esperando++;
        case ResultadoEnvioPedido.errorRecuperable:
          conError++;
        case ResultadoEnvioPedido.sesionCaducada:
          sesionCaducada = true;
      }
      if (sesionCaducada) break;
    }

    return ResultadoEnvioPedidos(
      sincronizados: sincronizados,
      conError: conError,
      esperandoCliente: esperando,
      sesionCaducada: sesionCaducada,
    );
  }

  /// Envía un único pedido con `POST /pedidos`. Antes de la llamada
  /// resuelve el `clienteId` desde el `clienteIdLocal` del pedido: si el
  /// cliente todavía no se sincronizó, se aborta el envío con
  /// [ResultadoEnvioPedido.esperandoCliente].
  Future<ResultadoEnvioPedido> reenviarUno(Pedido pedido) async {
    final cliente = await _clientesDao.obtenerPorIdLocal(pedido.clienteIdLocal);
    if (cliente == null || cliente.idServidor == null) {
      await _pedidosDao.marcarError(
        idLocal: pedido.idLocal,
        mensaje: 'Esperando a que se sincronice el cliente',
      );
      return ResultadoEnvioPedido.esperandoCliente;
    }

    final request = CrearPedidoRequest(
      clienteId: cliente.idServidor!,
      lineas: pedido.lineas
          .map((l) => CrearLineaRequest(
                productoId: l.productoId,
                cantidade: l.cantidade,
                precio: l.precio,
                iva: l.iva,
                recargoEquivalencia: l.recargoEquivalencia,
              ))
          .toList(),
      observaciones: pedido.observaciones,
    );

    try {
      final respuesta = await _apiClient.dio.post(
        '/pedidos',
        data: request.toJson(),
      );
      final json = respuesta.data as Map<String, dynamic>;
      await _pedidosDao.marcarSincronizado(
        idLocal: pedido.idLocal,
        idServidor: json['id'] as int,
        idOdoo: json['idOdoo'] as String?,
        numero: json['numero'] as String?,
        estadoPedido:
            EstadoPedido.desdeBackend(json['estadoPedido'] as String?),
        totalBase: (json['totalBase'] as num?)?.toDouble() ?? 0.0,
        totalIva: (json['totalIva'] as num?)?.toDouble() ?? 0.0,
        totalRE: (json['totalRE'] as num?)?.toDouble() ?? 0.0,
        total: (json['total'] as num?)?.toDouble() ?? 0.0,
      );
      return ResultadoEnvioPedido.sincronizado;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return ResultadoEnvioPedido.sesionCaducada;
      }
      await _pedidosDao.marcarError(
        idLocal: pedido.idLocal,
        mensaje: _mensajeErrorRed(e),
      );
      return ResultadoEnvioPedido.errorRecuperable;
    } catch (e) {
      if (kDebugMode) debugPrint('SyncPedidosService: error inesperado: $e');
      await _pedidosDao.marcarError(
        idLocal: pedido.idLocal,
        mensaje: 'Error inesperado: $e',
      );
      return ResultadoEnvioPedido.errorRecuperable;
    }
  }

  /// Traduce los errores de red de Dio a un mensaje legible.
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
