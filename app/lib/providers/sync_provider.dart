import 'package:flutter/foundation.dart';

import '../core/db/dao/sync_metadata_dao.dart';
import '../services/sync_clientes_service.dart';
import 'catalogos_provider.dart';
import 'clientes_provider.dart';

/// Resultado completo de una sincronización: contadores de lo descargado y
/// lo enviado, más una bandera por si la sesión se cortó por 401.
class ResultadoSincronizacion {
  final int modos;
  final int condiciones;
  final int clientesBajados;
  final int clientesSubidos;
  final int clientesConError;
  final bool sesionCaducada;

  const ResultadoSincronizacion({
    required this.modos,
    required this.condiciones,
    required this.clientesBajados,
    required this.clientesSubidos,
    required this.clientesConError,
    required this.sesionCaducada,
  });

  /// Resumen de una línea apto para mostrar en un SnackBar.
  String resumen() {
    if (sesionCaducada) {
      return 'Sesión caducada al sincronizar. Vuelve a iniciar sesión.';
    }
    final partes = <String>[
      '$modos modos / $condiciones condiciones',
      '$clientesBajados clientes descargados',
      '$clientesSubidos enviados',
    ];
    if (clientesConError > 0) {
      partes.add('$clientesConError con error');
    }
    return 'Sincronización completada · ${partes.join(' · ')}';
  }
}

/// Orquesta la sincronización completa con el servidor: catálogos, clientes
/// descendentes y envío de pendientes ascendentes, en ese orden.
///
/// La marca temporal `ultimaSync` solo avanza cuando toda la cadena termina
/// con éxito (sin 401), para evitar dejarla en un estado inconsistente si
/// algún paso intermedio falla.
class SyncProvider extends ChangeNotifier {
  final CatalogosProvider _catalogos;
  final ClientesProvider _clientes;
  final SyncClientesService _syncClientes;
  final SyncMetadataDao _metadataDao;

  SyncProvider(
    this._catalogos,
    this._clientes,
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
      // Evita arrancar dos sincronizaciones a la vez si el usuario pulsa
      // el botón mientras hay una en curso.
      return _ultimoResultado ?? const ResultadoSincronizacion(
        modos: 0,
        condiciones: 0,
        clientesBajados: 0,
        clientesSubidos: 0,
        clientesConError: 0,
        sesionCaducada: false,
      );
    }
    _sincronizando = true;
    _ultimoError = null;
    notifyListeners();

    try {
      final ultimaSync = await _metadataDao.obtenerUltimaSync();

      final resCatalogos = await _catalogos.sincronizarConServidor(ultimaSync);
      final nClientes = await _clientes.sincronizarDesdeServidor(ultimaSync);
      final resEnvio = await _syncClientes.enviarPendientes();

      // Refresca la lista en memoria para reflejar los cambios de estado
      // que ha hecho el envío (PENDENTE → SINCRONIZADO / ERRO).
      await _clientes.recargarDesdeLocal();

      // Solo avanzamos la marca si toda la sincronización terminó limpia.
      // Si la sesión caducó, la próxima sincronización empezará en el
      // mismo punto, para que no se pierda nada al reautenticarse.
      if (!resEnvio.sesionCaducada) {
        await _metadataDao.guardarUltimaSync(DateTime.now());
      }

      final resultado = ResultadoSincronizacion(
        modos: resCatalogos.modos,
        condiciones: resCatalogos.condiciones,
        clientesBajados: nClientes,
        clientesSubidos: resEnvio.sincronizados,
        clientesConError: resEnvio.conError,
        sesionCaducada: resEnvio.sesionCaducada,
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
