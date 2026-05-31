import 'package:flutter/foundation.dart';

import '../core/db/dao/productos_dao.dart';
import '../models/producto.dart';
import '../services/productos_service.dart';

/// Estado en memoria del catálogo de productos.
///
/// La fuente de verdad es SQLite: el provider lee de ahí para pintar la UI y
/// solo va al servidor cuando alguien llama explícitamente a
/// [sincronizarConServidor] (lo hace el [SyncProvider] durante la
/// sincronización descendente).
class ProductosProvider extends ChangeNotifier {
  final ProductosService _service;
  final ProductosDao _dao;

  ProductosProvider(this._service, this._dao);

  /// Lista completa cargada desde SQLite (sin filtrar). El filtrado se hace
  /// en memoria en el getter [productos] para que las tildes y la `ñ`
  /// funcionen, cosa que el `LIKE` de SQLite no soporta.
  List<Producto> _todos = const [];
  String _filtro = '';
  bool _cargando = false;

  String get filtro => _filtro;
  bool get cargando => _cargando;

  /// Productos filtrados por el texto de búsqueda (sobre descripción,
  /// referencia y código de barras).
  List<Producto> get productos {
    final texto = _filtro.trim().toLowerCase();
    if (texto.isEmpty) return _todos;
    bool casa(String? valor) =>
        valor != null && valor.toLowerCase().contains(texto);
    return _todos.where((p) {
      return casa(p.descripcion) || casa(p.referencia) || casa(p.codigoBarras);
    }).toList(growable: false);
  }

  /// Carga la lista completa desde SQLite. Se llama al arrancar la app y
  /// tras cada sincronización para refrescar lo que ya estaba en memoria.
  Future<void> cargarDesdeLocal() async {
    _cargando = true;
    notifyListeners();
    _todos = await _dao.listar();
    _cargando = false;
    notifyListeners();
  }

  /// Cambia el filtro de búsqueda. No relee SQLite: el filtrado es en memoria.
  void aplicarFiltro(String nuevoFiltro) {
    if (nuevoFiltro == _filtro) return;
    _filtro = nuevoFiltro;
    notifyListeners();
  }

  /// Sincroniza el catálogo con el servidor: pide los productos modificados
  /// desde [desde] (o el catálogo completo si es null) y los persiste en
  /// SQLite con upsert.
  ///
  /// Deliberadamente no actualiza la marca temporal global de sincronización:
  /// esa marca la avanza el [SyncProvider] una sola vez al terminar toda la
  /// cadena (catálogos + productos + clientes + envíos) con éxito, para
  /// evitar dejarla en estado inconsistente si algún paso posterior falla.
  ///
  /// Devuelve cuántos productos trajo el servidor.
  Future<int> sincronizarConServidor(DateTime? desde) async {
    final productos = await _service.listar(modificadoDesde: desde);
    await _dao.upsert(productos);
    await cargarDesdeLocal();

    if (kDebugMode) {
      debugPrint('ProductosProvider: sincronizados ${productos.length} productos '
          '${desde == null ? '(carga completa)' : '(desde $desde)'}');
    }

    return productos.length;
  }

  /// Devuelve un producto por su id del servidor. Útil cuando una línea de
  /// pedido referencia un producto y la UI necesita repintarlo: la línea
  /// guarda solo el id, no la entidad entera.
  Future<Producto?> obtener(int id) {
    return _dao.obtenerPorId(id);
  }
}
