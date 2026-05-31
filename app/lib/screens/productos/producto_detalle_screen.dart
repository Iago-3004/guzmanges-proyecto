import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/producto.dart';
import '../../providers/productos_provider.dart';

/// Vista de solo lectura con el detalle de un producto.
///
/// Recibe el id del servidor y resuelve la entidad contra SQLite. Se hace así
/// (en vez de pasar el [Producto] entero) para que si el producto se actualiza
/// en la BD mientras la pantalla está abierta (p. ej. tras una sincronización),
/// se reflejen los cambios al rehacer un setState.
class ProductoDetalleScreen extends StatefulWidget {
  final int id;

  const ProductoDetalleScreen({super.key, required this.id});

  @override
  State<ProductoDetalleScreen> createState() => _ProductoDetalleScreenState();
}

class _ProductoDetalleScreenState extends State<ProductoDetalleScreen> {
  late Future<Producto?> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = context.read<ProductosProvider>().obtener(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Producto?>(
      future: _futuro,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: const Text('Producto')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final producto = snapshot.data;
        if (producto == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Producto')),
            body: const Center(child: Text('Producto no encontrado')),
          );
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Producto')),
          body: _construirContenido(context, producto),
        );
      },
    );
  }

  Widget _construirContenido(BuildContext context, Producto producto) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _Cabecera(producto: producto),
        const SizedBox(height: 16),
        _SeccionCard(
          icono: Icons.qr_code_2,
          titulo: 'Identificación',
          filas: [
            _FilaCampo(
              icono: Icons.tag,
              etiqueta: 'Referencia',
              valor: producto.referencia,
            ),
            _FilaCampo(
              icono: Icons.qr_code_scanner,
              etiqueta: 'Código de barras',
              valor: producto.codigoBarras,
            ),
            _FilaCampo(
              icono: Icons.category_outlined,
              etiqueta: 'Tipo',
              valor: producto.tipoProducto,
            ),
          ],
        ),
        _SeccionCard(
          icono: Icons.euro_outlined,
          titulo: 'Precio e impuestos',
          filas: [
            _FilaCampo(
              icono: Icons.sell_outlined,
              etiqueta: 'Precio de venta (sin IVA)',
              valor: producto.precioVenta != null
                  ? _formatearPrecio(producto.precioVenta!)
                  : null,
            ),
            _FilaCampo(
              icono: Icons.percent,
              etiqueta: 'IVA por defecto',
              valor: producto.iva != null
                  ? '${_formatearPorcentaje(producto.iva!)} %'
                  : null,
            ),
          ],
        ),
        if (producto.observaciones != null && producto.observaciones!.isNotEmpty)
          _SeccionCard(
            icono: Icons.notes,
            titulo: 'Observaciones',
            filas: [
              _FilaCampo(
                icono: Icons.subject,
                etiqueta: 'Notas',
                valor: producto.observaciones,
              ),
            ],
          ),
      ],
    );
  }

  /// Formato simple de precio en euros con dos decimales y separador de miles
  /// como punto. No usa Intl para no añadir dependencias.
  String _formatearPrecio(double valor) {
    final entero = valor.truncate();
    final decimales = ((valor - entero) * 100).round().abs().toString().padLeft(2, '0');
    final enteroStr = entero
        .toString()
        .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return '$enteroStr,$decimales €';
  }

  /// Formato de un porcentaje sin decimales si es entero (21), con uno si no
  /// (1.4). Evita mostrar "21.00" en el caso típico de IVA.
  String _formatearPorcentaje(double valor) {
    if (valor == valor.truncate()) {
      return valor.truncate().toString();
    }
    return valor.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}

// =============================================================================
// Cabecera con la descripción del producto, su chip de stock y el precio
// =============================================================================

class _Cabecera extends StatelessWidget {
  final Producto producto;

  const _Cabecera({required this.producto});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            scheme.primaryContainer.withValues(alpha: 0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              _inicial(producto.descripcion),
              style: TextStyle(
                color: scheme.onPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 28,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  producto.descripcion,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onPrimaryContainer,
                      ),
                ),
                const SizedBox(height: 6),
                _ChipStock(stock: producto.stock),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _inicial(String desc) {
    final limpio = desc.trim();
    if (limpio.isEmpty) return '?';
    return limpio.substring(0, 1).toUpperCase();
  }
}

// =============================================================================
// Card de sección con icono, título y filas
// =============================================================================

class _SeccionCard extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final List<_FilaCampo> filas;

  const _SeccionCard({
    required this.icono,
    required this.titulo,
    required this.filas,
  });

  @override
  Widget build(BuildContext context) {
    final visibles = filas.where((f) => f.tieneValor).toList();
    if (visibles.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icono, color: scheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    titulo,
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ...visibles,
            ],
          ),
        ),
      ),
    );
  }
}

class _FilaCampo extends StatelessWidget {
  final IconData icono;
  final String etiqueta;
  final String? valor;

  const _FilaCampo({
    required this.icono,
    required this.etiqueta,
    required this.valor,
  });

  bool get tieneValor => valor != null && valor!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!tieneValor) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor!,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Chip que muestra el stock disponible (cacheado de la última sincronización)
// =============================================================================

class _ChipStock extends StatelessWidget {
  final int? stock;

  const _ChipStock({required this.stock});

  @override
  Widget build(BuildContext context) {
    final s = stock ?? 0;
    final hayStock = s > 0;
    final color = hayStock ? Colors.green.shade700 : Colors.red.shade700;
    final texto =
        hayStock ? 'Stock disponible: $s' : 'Sin stock disponible';
    final icono = hayStock ? Icons.inventory_2_outlined : Icons.block;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            texto,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
