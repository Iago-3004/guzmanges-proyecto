import 'package:flutter/foundation.dart';

import '../core/db/dao/sync_metadata_dao.dart';
import '../services/sync_clientes_service.dart';
import 'catalogos_provider.dart';
import 'clientes_provider.dart';
import 'pedidos_provider.dart';
import 'productos_provider.dart';

/// Resultado completo de una sincronización: contadores de lo descargado y
/// lo enviado para cada tipo de entidad, más una bandera por si la sesión
/// se cortó por 401.
class ResultadoSincronizacion {
  final int modos;
  final int condiciones;
  final int productosBajados;
  final int clientesBajados;
  final int clientesSubidos;
  final int clientesConError;
  final int pedidosBajados;
  final int pedidosSubidos;
  final int pedidosConError;

  /// Cuántos pedidos no se pudieron enviar porque su cliente todavía no
  /// estaba sincronizado. Se incluyen también en [pedidosConError]; este
  /// subcontador permite a la UI explicar el motivo principal.
  final int pedidosEsperandoCliente;

  final bool sesionCaducada;

  const ResultadoSincronizacion({
    required this.modos,
    required this.condiciones,
    required this.productosBajados,
    required this.clientesBajados,
    required this.clientesSubidos,
    required this.clientesConError,
    required this.pedidosBajados,
    required this.pedidosSubidos,
    required this.pedidosConError,
    required this.pedidosEsperandoCliente,
    required this.sesionCaducada,
  });

  /// true si hay algún tipo de error que conviene mostrarle al usuario en
  /// un diálogo (no en un SnackBar). Sincronizar es una operación que el
  /// usuario inicia explícitamente, y se merece saber si algo no fue bien.
  bool get hayErrores => clientesConError > 0 || pedidosConError > 0;

  const ResultadoSincronizacion.vacio()
      : modos = 0,
        condiciones = 0,
        productosBajados = 0,
        clientesBajados = 0,
        clientesSubidos = 0,
        clientesConError = 0,
        pedidosBajados = 0,
        pedidosSubidos = 0,
        pedidosConError = 0,
        pedidosEsperandoCliente = 0,
        sesionCaducada = false;
}

/// Orquesta la sincronización completa con el servidor en este orden:
///
///   catálogos → productos → clientes descendente → clientes ascendente →
///   pedidos descendente → pedidos ascendente
///
/// El orden importa: los pedidos ascendentes van **después** de los clientes
/// ascendentes para que, si un pedido depende de un cliente recién creado en
/// local, esa misma vuelta pueda resolver la dependencia (el cliente ya tiene
/// id de servidor cuando le toca al pedido).
///
/// La marca temporal `ultimaSync` solo avanza cuando toda la cadena termina
/// sin un 401, para evitar dejarla en un estado inconsistente si algún paso
/// intermedio falla por sesión caducada.
class SyncProvider extends ChangeNotifier {
  final CatalogosProvider _catalogos;
  final ProductosProvider _productos;
  final ClientesProvider _clientes;
  final PedidosProvider _pedidos;
  final SyncClientesService _syncClientes;
  final SyncMetadataDao _metadataDao;

  SyncProvider(
    this._catalogos,
    this._productos,
    this._clientes,
    this._pedidos,
    this._syncClientes,
    this._metadataDao,
  );

  bool _sincronizando = false;
  String? _ultimoError;
  ResultadoSincronizacion? _ultimoResultado;

  bool get sincronizando => _sincronizando;
  String? get ultimoError => _ultimoError;
  ResultadoSincronizacion? get ultimoResultado => _ultimoResultado;

  /// Ejecuta una sincronización completa. Lanza [Exception] si algún paso
  /// falla por red o por error del servidor; en cambio, los errores por
  /// fila al subir pendientes no abortan: quedan reflejados en el resultado.
  Future<ResultadoSincronizacion> sincronizarTodo() async {
    if (_sincronizando) {
      return _ultimoResultado ?? const ResultadoSincronizacion.vacio();
    }
    _sincronizando = true;
    _ultimoError = null;
    notifyListeners();

    try {
      final ultimaSync = await _metadataDao.obtenerUltimaSync();

      // --- Descendente: catálogos → productos → clientes → pedidos ---
      final resCatalogos = await _catalogos.sincronizarConServidor(ultimaSync);
      final nProductos = await _productos.sincronizarConServidor(ultimaSync);
      final nClientes = await _clientes.sincronizarDesdeServidor(ultimaSync);
      final nPedidosBajados =
          await _pedidos.sincronizarDesdeServidor(ultimaSync);

      // --- Ascendente: clientes → pedidos (en este orden, por dependencias) ---
      final resEnvioClientes = await _syncClientes.enviarPendientes();
      await _clientes.recargarDesdeLocal();

      // Si la sesión caducó al subir clientes, no tiene sentido intentar
      // subir pedidos (también dará 401). Se devuelve lo que tengamos.
      final resEnvioPedidos = resEnvioClientes.sesionCaducada
          ? null
          : await _pedidos.enviarPendientesAlServidor();

      // Solo avanzamos la marca si nada cortó por 401, para que la próxima
      // sincronización empiece exactamente donde se quedó.
      final huboSesionCaducada = resEnvioClientes.sesionCaducada ||
          (resEnvioPedidos?.sesionCaducada ?? false);
      if (!huboSesionCaducada) {
        await _metadataDao.guardarUltimaSync(DateTime.now());
      }

      final resultado = ResultadoSincronizacion(
        modos: resCatalogos.modos,
        condiciones: resCatalogos.condiciones,
        productosBajados: nProductos,
        clientesBajados: nClientes,
        clientesSubidos: resEnvioClientes.sincronizados,
        clientesConError: resEnvioClientes.conError,
        pedidosBajados: nPedidosBajados,
        pedidosSubidos: resEnvioPedidos?.sincronizados ?? 0,
        pedidosConError: resEnvioPedidos?.conError ?? 0,
        pedidosEsperandoCliente: resEnvioPedidos?.esperandoCliente ?? 0,
        sesionCaducada: huboSesionCaducada,
      );
      _ultimoResultado = resultado;
      _sincronizando = false;
      notifyListeners();
      return resultado;
    } catch (e) {
      _ultimoError = e.toString().replaceFirst('Exception: ', '');
      _sincronizando = false;
      notifyListeners();
      rethrow;
    }
  }
}
