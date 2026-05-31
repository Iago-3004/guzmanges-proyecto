import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/db/dao/clientes_dao.dart';
import '../dto/crear_cliente_request.dart';
import '../models/cliente.dart';
import '../services/clientes_service.dart';

/// Estado en memoria de la lista de clientes.
///
/// La fuente de verdad es SQLite: el provider lee de ahí para pintar la UI
/// y solo va al servidor cuando alguien llama explícitamente a
/// [sincronizarDesdeServidor]. Los clientes con `estadoSync = pendente`
/// (creados localmente) nunca se sobrescriben al sincronizar.
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
  bool _filtroSoloPendientes = false;
  bool _cargando = false;

  String get filtro => _filtro;
  int? get filtroModoPagoId => _filtroModoPagoId;
  int? get filtroCondicionPagoId => _filtroCondicionPagoId;
  bool get filtroSoloPendientes => _filtroSoloPendientes;
  bool get cargando => _cargando;

  /// Número de filtros (aparte del texto) actualmente activos. Útil para
  /// mostrar un badge junto al botón de filtros.
  int get numeroFiltrosActivos =>
      (_filtroModoPagoId != null ? 1 : 0) +
      (_filtroCondicionPagoId != null ? 1 : 0) +
      (_filtroSoloPendientes ? 1 : 0);

  /// Lista de clientes a mostrar, aplicando el texto de búsqueda y los
  /// filtros activos sobre la lista completa.
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
      // "Solo pendientes" se interpreta como "todavía no sincronizados":
      // entran PENDENTE y ERRO de envío. Los SINCRONIZADO se filtran.
      if (_filtroSoloPendientes &&
          c.estadoSync == EstadoSync.sincronizado) {
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

  /// Activa o desactiva el filtro "solo pendientes de sincronizar".
  void aplicarFiltroSoloPendientes(bool valor) {
    if (valor == _filtroSoloPendientes) return;
    _filtroSoloPendientes = valor;
    notifyListeners();
  }

  /// Resetea todos los filtros del panel desplegable (no toca el texto del
  /// buscador, que tiene su propia limpieza).
  void limpiarFiltrosDespegable() {
    if (_filtroModoPagoId == null &&
        _filtroCondicionPagoId == null &&
        !_filtroSoloPendientes) {
      return;
    }
    _filtroModoPagoId = null;
    _filtroCondicionPagoId = null;
    _filtroSoloPendientes = false;
    notifyListeners();
  }

  /// Sincroniza la lista de clientes con el servidor: pide los modificados
  /// desde [desde] (todos si es null) y hace upsert en SQLite reutilizando
  /// los `id_local` ya existentes.
  ///
  /// Deliberadamente no actualiza la marca temporal global de sincronización:
  /// esa marca debe actualizarse una sola vez al terminar toda la cadena
  /// (catálogos + clientes + envío de pendientes) con éxito; si se hiciera
  /// aquí, un fallo posterior dejaría una marca inconsistente.
  ///
  /// Devuelve cuántos clientes ha traído del servidor.
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

  /// Elimina un cliente de la base local. Solo se permite borrar clientes
  /// que aún no se han subido al servidor (`idServidor == null`): los ya
  /// sincronizados se volverían a descargar en la próxima sincronización,
  /// así que borrarlos en local no aportaría nada.
  ///
  /// Lanza [StateError] si se intenta borrar un cliente ya sincronizado.
  Future<void> eliminarClienteLocal(String idLocal) async {
    final cliente = await _dao.obtenerPorIdLocal(idLocal);
    if (cliente == null) return;
    if (cliente.idServidor != null) {
      throw StateError(
          'No se puede eliminar localmente un cliente ya sincronizado con el servidor.');
    }
    await _dao.eliminarPorIdLocal(idLocal);
    await recargarDesdeLocal();
  }

  /// Devuelve los clientes locales que ya tienen el mismo [cif] (mayúsculas
  /// y minúsculas se ignoran). Pensado para avisar al dar de alta un cliente
  /// nuevo cuyo CIF ya esté en la BD local.
  Future<List<Cliente>> buscarCoincidenciasPorCif(String cif) {
    return _dao.buscarPorCif(cif);
  }

  /// Da de alta un cliente nuevo en SQLite con `estadoSync = PENDENTE`.
  ///
  /// **No llama a la API.** El cliente queda pendiente de envío hasta que
  /// se dispare una sincronización ascendente. Así se garantiza que el
  /// alta funciona aunque no haya conexión en ese momento.
  ///
  /// Las descripciones de modo y condición de pago se reciben ya resueltas
  /// desde el formulario (que las saca de [CatalogosProvider]) para que el
  /// detalle del cliente pueda mostrar texto legible aunque aún no se haya
  /// sincronizado con el servidor.
  ///
  /// [comercial] es el nombre del preventa autenticado, guardado en local
  /// solo a efectos informativos; al sincronizar, la API devolverá la
  /// versión definitiva.
  Future<Cliente> crearCliente(
    CrearClienteRequest req, {
    String? modoPagoDescripcion,
    String? condicionPagoDescripcion,
    String? comercial,
  }) async {
    final ahora = DateTime.now();
    final cliente = Cliente(
      idLocal: _uuid.v4(),
      idServidor: null,
      idOdoo: null,
      nombreComercial: req.nombreComercial,
      razonSocial: req.razonSocial,
      cif: req.cif,
      direccion: req.direccion,
      localidad: req.localidad,
      codigoPostal: req.codigoPostal,
      provincia: req.provincia,
      telefono: req.telefono,
      movil: req.movil,
      email: req.email,
      modoPagoId: req.modoPagoId,
      modoPagoDescripcion: modoPagoDescripcion,
      condicionPagoId: req.condicionPagoId,
      condicionPagoDescripcion: condicionPagoDescripcion,
      comercial: comercial,
      activo: true,
      estadoSync: EstadoSync.pendente,
      actualizadoEn: ahora,
      creadoEn: ahora,
    );
    await _dao.insertarLocal(cliente);
    await recargarDesdeLocal();
    return cliente;
  }
}
