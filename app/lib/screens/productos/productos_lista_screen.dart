import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/productos_provider.dart';
import '../../widgets/producto_tile.dart';
import 'producto_detalle_screen.dart';

/// Pantalla con el catálogo de productos en caché local.
///
/// Lee siempre de SQLite (vía [ProductosProvider]); la sincronización con el
/// servidor se dispara desde el botón "Sincronizar" del Home, no desde aquí.
/// Permite búsqueda por texto (descripción, referencia o código de barras).
class ProductosListaScreen extends StatefulWidget {
  const ProductosListaScreen({super.key});

  @override
  State<ProductosListaScreen> createState() => _ProductosListaScreenState();
}

class _ProductosListaScreenState extends State<ProductosListaScreen> {
  final TextEditingController _buscador = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Refresca al entrar por si la BD cambió desde otra pantalla (p. ej.
    // tras una sincronización lanzada desde el Home).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductosProvider>().cargarDesdeLocal();
    });
  }

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductosProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos'),
      ),
      body: Column(
        children: [
          _buscadorYContador(context, provider),
          const _PanelFiltros(),
          Expanded(child: _construirCuerpo(context, provider)),
        ],
      ),
    );
  }

  Widget _buscadorYContador(BuildContext context, ProductosProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _buscador,
            decoration: InputDecoration(
              hintText: 'Buscar por descripción, referencia o código',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _buscador.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _buscador.clear();
                        context.read<ProductosProvider>().aplicarFiltro('');
                      },
                    ),
              isDense: true,
            ),
            onChanged: (texto) {
              context.read<ProductosProvider>().aplicarFiltro(texto);
            },
          ),
          if (!provider.cargando && provider.productos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                '${provider.productos.length} '
                '${provider.productos.length == 1 ? "producto" : "productos"}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _construirCuerpo(BuildContext context, ProductosProvider provider) {
    if (provider.cargando && provider.productos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.productos.isEmpty) {
      return _MensajeVacio(
        hayFiltro: provider.filtro.isNotEmpty ||
            provider.numeroFiltrosActivos > 0,
      );
    }
    return RefreshIndicator(
      onRefresh: () => context.read<ProductosProvider>().cargarDesdeLocal(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        itemCount: provider.productos.length,
        itemBuilder: (context, index) {
          final producto = provider.productos[index];
          return ProductoTile(
            producto: producto,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProductoDetalleScreen(id: producto.id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// =============================================================================
// Panel de filtros desplegable (ordenación, tipo, solo sin stock)
// =============================================================================

class _PanelFiltros extends StatelessWidget {
  const _PanelFiltros();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = context.watch<ProductosProvider>();
    final activos = provider.numeroFiltrosActivos;

    return Theme(
      // ExpansionTile aplica un divider en M3; lo quitamos para integrarlo
      // mejor con el resto de la cabecera.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(Icons.filter_list, color: scheme.primary),
        title: Row(
          children: [
            const Text('Filtros'),
            if (activos > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$activos',
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        trailing: activos > 0
            ? TextButton.icon(
                onPressed: () => context
                    .read<ProductosProvider>()
                    .limpiarFiltrosDesplegable(),
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('Limpiar'),
              )
            : null,
        childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          DropdownButtonFormField<OrdenProductos>(
            initialValue: provider.ordenacion,
            isExpanded: true,
            decoration: _decoracion('Ordenar por'),
            items: const [
              DropdownMenuItem(
                value: OrdenProductos.nombreAsc,
                child: Text('Nombre (A-Z)'),
              ),
              DropdownMenuItem(
                value: OrdenProductos.nombreDesc,
                child: Text('Nombre (Z-A)'),
              ),
              DropdownMenuItem(
                value: OrdenProductos.precioAsc,
                child: Text('Precio (menor primero)'),
              ),
              DropdownMenuItem(
                value: OrdenProductos.precioDesc,
                child: Text('Precio (mayor primero)'),
              ),
            ],
            onChanged: (valor) {
              if (valor != null) {
                context.read<ProductosProvider>().aplicarOrdenacion(valor);
              }
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: provider.filtroTipo,
            isExpanded: true,
            decoration: _decoracion('Tipo de producto'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
              for (final tipo in provider.tiposDisponibles)
                DropdownMenuItem<String?>(value: tipo, child: Text(tipo)),
            ],
            onChanged: (valor) {
              context.read<ProductosProvider>().aplicarFiltroTipo(valor);
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<FiltroStock>(
            initialValue: provider.filtroStock,
            isExpanded: true,
            decoration: _decoracion('Stock'),
            items: const [
              DropdownMenuItem(
                value: FiltroStock.todos,
                child: Text('Todos'),
              ),
              DropdownMenuItem(
                value: FiltroStock.conStock,
                child: Text('Solo con stock'),
              ),
              DropdownMenuItem(
                value: FiltroStock.sinStock,
                child: Text('Solo sin stock'),
              ),
            ],
            onChanged: (valor) {
              if (valor != null) {
                context.read<ProductosProvider>().aplicarFiltroStock(valor);
              }
            },
          ),
        ],
      ),
    );
  }

  /// Decoración común de los dos dropdowns. Usa siempre el label flotante
  /// (FloatingLabelBehavior.always) y un OutlineInputBorder con gapPadding
  /// generoso para que el texto del label no se vea cortado por el borde.
  InputDecoration _decoracion(String etiqueta) {
    return InputDecoration(
      labelText: etiqueta,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      border: const OutlineInputBorder(gapPadding: 8),
      enabledBorder: const OutlineInputBorder(gapPadding: 8),
      focusedBorder: const OutlineInputBorder(gapPadding: 8),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}

/// Mensaje cuando la lista está vacía. Diferencia "no hay resultados" (filtro
/// demasiado restrictivo) de "no hay productos en local" (primera ejecución
/// sin sincronizar).
class _MensajeVacio extends StatelessWidget {
  final bool hayFiltro;

  const _MensajeVacio({required this.hayFiltro});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hayFiltro ? Icons.search_off : Icons.inventory_2_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              hayFiltro
                  ? 'Ningún producto coincide con la búsqueda.'
                  : 'No hay productos en local.\nPulsa "Sincronizar" en la pantalla principal para descargarlos.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
