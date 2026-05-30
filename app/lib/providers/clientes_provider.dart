import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/db/dao/clientes_dao.dart';
import '../models/cliente.dart';
import '../services/clientes_service.dart';

/// Estado en memoria de la lista de clientes.
///
/// La fuente de verdad es SQLite: el provider lee de ahí para pintar la UI y
/// solo va al servidor cuando lo lanza el [SyncProvider] (FAB Sincronizar o
/// diálogo tras login). Los clientes con `estadoSync = pendente` (creados
/// localmente) nunca se sobrescriben al sincronizar desde el servidor.
class ClientesProvider extends ChangeNotifier {
  final ClientesService _service;
  final ClientesDao _dao;
  final Uuid _uuid;

  ClientesProvider(this._service, this._dao, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  /// Lista completa cargada desde SQLite (sin filtrar). El filtrado se hace
  /// en memoria en el getter [clientes] para que `ñ` y acentos funcionen,
  /// cosa que el `LIKE` de SQLite no soporta.
  List<Cliente> _todosClientes = const [];
  String _filtro = '';
  int? _filtroModoPagoId;
  int? _filtroCondicionPagoId;
  bool _cargando = false;

  String get filtro => _filtro;
  int? get filtroModoPagoId => _filtroModoPagoId;
  int? get filtroCondicionPagoId => _filtroCondicionPagoId;
  bool get cargando => _cargando;

  /// Número de filtros (aparte del texto) actualmente activos. Útil para
  /// mostrar un badge junto al botón de filtros.
  int get numeroFiltrosActivos =>
      (_filtroModoPagoId != null ? 1 : 0) +
      (_filtroCondicionPagoId != null ? 1 : 0);

  /// Lista de clientes a mostrar, aplicando el texto de búsqueda y los
  /// filtros de modo / condición de pago sobre la lista completa.
  List<Cliente> get clientes {
    final texto = _filtro.trim().toLowerCase();
    return _todosClientes.where((c) {
      if (texto.isNotEmpty) {
        bool casa(String? valor) =>
            valor != null && valor.toLowerCase().contains(texto);
        if (!casa(c.nombreComercial) && !casa(c.razonSocial) && !casa(c.cif)) {
          return false;
        }
      }
      if (_filtroModoPagoId != null && c.modoPagoId != _filtroModoPagoId) {
        return false;
      }
      if (_filtroCondicionPagoId != null &&
          c.condicionPagoId != _filtroCondicionPagoId) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  /// Carga la lista completa de clientes desde SQLite.
  Future<void> recargarDesdeLocal() async {
    _cargando = true;
    notifyListeners();
    _todosClientes = await _dao.listar();
    _cargando = false;
    notifyListeners();
  }

  /// Cambia el filtro de búsqueda de texto.
  void aplicarFiltro(String nuevoFiltro) {
    if (nuevoFiltro == _filtro) return;
    _filtro = nuevoFiltro;
    notifyListeners();
  }

  /// Cambia el filtro por modo de pago. Pasa `null` para limpiar el filtro.
  void aplicarFiltroModoPago(int? idModoPago) {
    if (idModoPago == _filtroModoPagoId) return;
    _filtroModoPagoId = idModoPago;
    notifyListeners();
  }

  /// Cambia el filtro por condición de pago. Pasa `null` para limpiar.
  void aplicarFiltroCondicionPago(int? idCondicionPago) {
    if (idCondicionPago == _filtroCondicionPagoId) return;
    _filtroCondicionPagoId = idCondicionPago;
    notifyListeners();
  }

  /// Limpia los filtros de modo / condición de pago (no toca el texto).
  void limpiarFiltrosDespegable() {
    if (_filtroModoPagoId == null && _filtroCondicionPagoId == null) return;
    _filtroModoPagoId = null;
    _filtroCondicionPagoId = null;
    notifyListeners();
  }

  /// Sincroniza la lista de clientes con el servidor: pide los modificados
  /// desde [desde] (todos si es null) y hace upsert en SQLite reusando los
  /// `id_local` existentes.
  ///
  /// No actualiza la marca temporal global ([SyncMetadataDao]); eso lo hará
  /// el [SyncProvider] al final de toda la sincronización.
  ///
  /// Devuelve cuántos clientes se han traído del servidor.
  Future<int> sincronizarDesdeServidor(DateTime? desde) async {
    final jsons = await _service.listar(modificadoDesde: desde);
    for (final json in jsons) {
      final cliente = Cliente.desdeServidor(
        json,
        idLocal: _uuid.v4(),
      );
      await _dao.upsertDesdeServidor(cliente);
    }
    // Refresca el estado en memoria con lo que hay ahora en SQLite.
    await recargarDesdeLocal();

    if (kDebugMode) {
      debugPrint('ClientesProvider: sincronizados ${jsons.length} clientes '
          '${desde == null ? '(carga completa)' : '(desde $desde)'}');
    }

    return jsons.length;
  }

  /// Recupera un cliente por su id local (UUID). Útil para la pantalla de
  /// detalle.
  Future<Cliente?> obtener(String idLocal) {
    return _dao.obtenerPorIdLocal(idLocal);
  }
}
