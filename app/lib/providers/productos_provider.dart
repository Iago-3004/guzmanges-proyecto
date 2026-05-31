import 'package:flutter/foundation.dart';

import '../core/db/dao/productos_dao.dart';
import '../models/producto.dart';
import '../services/productos_service.dart';

/// Criterio de ordenación de la lista de productos.
enum OrdenProductos {
  /// Por descripción, A a Z (la ordenación por defecto al abrir la pantalla).
  nombreAsc,
  /// Por descripción, Z a A.
  nombreDesc,
  /// Por precio de venta de menor a mayor; los productos sin precio van al final.
  precioAsc,
  /// Por precio de venta de mayor a menor; los productos sin precio van al final.
  precioDesc,
}

/// Filtro de stock de la lista de productos.
enum FiltroStock {
  /// Mostrar todos los productos (default).
  todos,
  /// Solo productos con stock disponible (> 0).
  conStock,
  /// Solo productos sin stock (0 o null).
  sinStock,
}

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

  /// Lista completa cargada desde SQLite (sin filtrar). El filtrado y la
  /// ordenación se hacen en memoria en el getter [productos] para que las
  /// tildes y la `ñ` funcionen (cosa que el `LIKE` de SQLite no soporta) y
  /// para no relanzar consultas a la BD por cada cambio de filtro.
  List<Producto> _todos = const [];
  String _filtro = '';
  FiltroStock _filtroStock = FiltroStock.todos;
  String? _filtroTipo;
  OrdenProductos _ordenacion = OrdenProductos.nombreAsc;
  bool _cargando = false;

  String get filtro => _filtro;
  FiltroStock get filtroStock => _filtroStock;
  String? get filtroTipo => _filtroTipo;
  OrdenProductos get ordenacion => _ordenacion;
  bool get cargando => _cargando;

  /// Tipos de producto disponibles en el catálogo cargado, ordenados
  /// alfabéticamente. Se usa para alimentar el dropdown de filtros sin
  /// hardcodearlos: si Odoo añade un tipo nuevo, aparece automáticamente.
  List<String> get tiposDisponibles {
    final tipos = <String>{};
    for (final p in _todos) {
      final t = p.tipoProducto;
      if (t != null && t.isNotEmpty) tipos.add(t);
    }
    final lista = tipos.toList()..sort();
    return lista;
  }

  /// Número de filtros (aparte del texto) actualmente activos. Útil para
  /// mostrar un badge junto al botón de filtros.
  int get numeroFiltrosActivos =>
      (_filtroStock != FiltroStock.todos ? 1 : 0) +
      (_filtroTipo != null ? 1 : 0) +
      (_ordenacion != OrdenProductos.nombreAsc ? 1 : 0);

  /// Productos a mostrar: aplica el texto de búsqueda, los filtros activos y
  /// la ordenación elegida sobre la lista completa.
  List<Producto> get productos {
    final texto = _filtro.trim().toLowerCase();
    final filtrados = _todos.where((p) {
      if (texto.isNotEmpty) {
        bool casa(String? valor) =>
            valor != null && valor.toLowerCase().contains(texto);
        if (!casa(p.descripcion) && !casa(p.referencia) && !casa(p.codigoBarras)) {
          return false;
        }
      }
      // "Sin stock" cubre stock 0 y stock null (Odoo a veces no lo informa).
      final s = p.stock ?? 0;
      switch (_filtroStock) {
        case FiltroStock.todos:
          break;
        case FiltroStock.conStock:
          if (s <= 0) return false;
        case FiltroStock.sinStock:
          if (s > 0) return false;
      }
      if (_filtroTipo != null && p.tipoProducto != _filtroTipo) {
        return false;
      }
      return true;
    }).toList();
    _ordenar(filtrados);
    return filtrados;
  }

  /// Aplica la ordenación elegida sobre la lista in-place.
  ///
  /// Para las ordenaciones por precio, los productos sin precio se mandan al
  /// final independientemente del sentido, para que no descoloquen la lista.
  void _ordenar(List<Producto> lista) {
    int cmpStr(String? a, String? b) =>
        (a ?? '').toLowerCase().compareTo((b ?? '').toLowerCase());
    switch (_ordenacion) {
      case OrdenProductos.nombreAsc:
        lista.sort((a, b) => cmpStr(a.descripcion, b.descripcion));
      case OrdenProductos.nombreDesc:
        lista.sort((a, b) => cmpStr(b.descripcion, a.descripcion));
      case OrdenProductos.precioAsc:
        lista.sort((a, b) {
          if (a.precioVenta == null && b.precioVenta == null) return 0;
          if (a.precioVenta == null) return 1;
          if (b.precioVenta == null) return -1;
          return a.precioVenta!.compareTo(b.precioVenta!);
        });
      case OrdenProductos.precioDesc:
        lista.sort((a, b) {
          if (a.precioVenta == null && b.precioVenta == null) return 0;
          if (a.precioVenta == null) return 1;
          if (b.precioVenta == null) return -1;
          return b.precioVenta!.compareTo(a.precioVenta!);
        });
    }
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

  /// Cambia el filtro de stock (todos / con stock / sin stock).
  void aplicarFiltroStock(FiltroStock valor) {
    if (valor == _filtroStock) return;
    _filtroStock = valor;
    notifyListeners();
  }

  /// Cambia el filtro por tipo de producto. Pasa `null` para limpiarlo.
  void aplicarFiltroTipo(String? tipo) {
    if (tipo == _filtroTipo) return;
    _filtroTipo = tipo;
    notifyListeners();
  }

  /// Cambia el criterio de ordenación de la lista.
  void aplicarOrdenacion(OrdenProductos orden) {
    if (orden == _ordenacion) return;
    _ordenacion = orden;
    notifyListeners();
  }

  /// Resetea todos los filtros del panel desplegable (no toca el texto del
  /// buscador, que tiene su propia limpieza).
  void limpiarFiltrosDesplegable() {
    if (_filtroStock == FiltroStock.todos &&
        _filtroTipo == null &&
        _ordenacion == OrdenProductos.nombreAsc) {
      return;
    }
    _filtroStock = FiltroStock.todos;
    _filtroTipo = null;
    _ordenacion = OrdenProductos.nombreAsc;
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
