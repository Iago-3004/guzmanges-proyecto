import 'package:flutter/foundation.dart';

import '../core/db/dao/catalogos_dao.dart';
import '../models/condicion_pago.dart';
import '../models/modo_pago.dart';
import '../services/catalogos_service.dart';

/// Estado en memoria de los catálogos de pago (modos y condiciones).
///
/// La lectura es siempre desde SQLite, para que los selectores funcionen
/// también sin conexión. La sincronización contra el servidor sólo se
/// dispara cuando alguien llama explícitamente a [sincronizarConServidor].
class CatalogosProvider extends ChangeNotifier {
  final CatalogosService _service;
  final CatalogosDao _dao;

  CatalogosProvider(this._service, this._dao);

  List<ModoPago> _modos = const [];
  List<CondicionPago> _condiciones = const [];
  bool _cargando = false;

  List<ModoPago> get modos => _modos;
  List<CondicionPago> get condiciones => _condiciones;
  bool get cargando => _cargando;

  /// Carga los catálogos desde SQLite. Se llama al arrancar la app y tras una
  /// sincronización con el servidor (para refrescar el estado en memoria).
  Future<void> cargarDesdeLocal() async {
    _cargando = true;
    notifyListeners();
    _modos = await _dao.listarModos();
    _condiciones = await _dao.listarCondiciones();
    _cargando = false;
    notifyListeners();
  }

  /// Sincroniza los catálogos con el servidor: pide a la API los modos y
  /// condiciones modificados desde [desde] (o todos si es null) y los guarda
  /// en SQLite con upsert.
  ///
  /// Deliberadamente no actualiza la marca temporal global de sincronización
  /// (`SyncMetadataDao`): esa marca se debe actualizar una sola vez, cuando
  /// toda la sincronización (catálogos + clientes + envío) termine con
  /// éxito; si la actualizase aquí, un fallo posterior dejaría una marca
  /// inconsistente.
  ///
  /// Devuelve cuántos modos y condiciones se han actualizado, para poder
  /// mostrarlo en un SnackBar de resumen.
  Future<({int modos, int condiciones})> sincronizarConServidor(
      DateTime? desde) async {
    final nuevosModos = await _service.listarModos(modificadoDesde: desde);
    final nuevasCondiciones =
        await _service.listarCondiciones(modificadoDesde: desde);

    await _dao.upsertModos(nuevosModos);
    await _dao.upsertCondiciones(nuevasCondiciones);

    // Refresca el estado en memoria con lo que hay ahora en SQLite (que ya
    // mezcla lo viejo con lo nuevo).
    await cargarDesdeLocal();

    if (kDebugMode) {
      debugPrint('CatalogosProvider: sincronizados '
          '${nuevosModos.length} modos / ${nuevasCondiciones.length} condiciones '
          '${desde == null ? '(carga completa)' : '(desde $desde)'}');
    }

    return (modos: nuevosModos.length, condiciones: nuevasCondiciones.length);
  }
}
