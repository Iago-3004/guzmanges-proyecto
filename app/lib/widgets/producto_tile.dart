import 'package:flutter/material.dart';

import '../models/producto.dart';

/// Fila de producto en el listado del catálogo. Muestra:
/// - Icono cuadrado con la inicial de la descripción.
/// - Descripción (principal).
/// - Referencia y código de barras como metadatos.
/// - Precio (sin IVA) destacado a la derecha.
/// - Chip de stock (verde si > 0, rojo si 0/null) bajo el precio.
class ProductoTile extends StatelessWidget {
  final Producto producto;
  final VoidCallback? onTap;

  const ProductoTile({
    super.key,
    required this.producto,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  _inicial(),
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      producto.descripcion,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _filaMetadatos(),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (producto.precioVenta != null)
                    Text(
                      _formatearPrecio(producto.precioVenta!),
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  const SizedBox(height: 4),
                  _ChipStock(stock: producto.stock),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filaMetadatos() {
    final hayRef =
        producto.referencia != null && producto.referencia!.isNotEmpty;
    final hayCodigo =
        producto.codigoBarras != null && producto.codigoBarras!.isNotEmpty;
    if (!hayRef && !hayCodigo) return const SizedBox.shrink();
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        if (hayRef)
          _Metadato(icono: Icons.tag, texto: producto.referencia!),
        if (hayCodigo)
          _Metadato(icono: Icons.qr_code_2, texto: producto.codigoBarras!),
      ],
    );
  }

  String _inicial() {
    final desc = producto.descripcion.trim();
    if (desc.isEmpty) return '?';
    return desc.substring(0, 1).toUpperCase();
  }

  /// Formato simple de precio en euros con dos decimales y separador de miles
  /// como punto (común en España). No usa Intl para no añadir dependencias.
  String _formatearPrecio(double valor) {
    final entero = valor.truncate();
    final decimales = ((valor - entero) * 100).round().abs().toString().padLeft(2, '0');
    final enteroStr = entero
        .toString()
        .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return '$enteroStr,$decimales €';
  }
}

class _Metadato extends StatelessWidget {
  final IconData icono;
  final String texto;

  const _Metadato({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 13, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          texto,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _ChipStock extends StatelessWidget {
  final int? stock;

  const _ChipStock({required this.stock});

  @override
  Widget build(BuildContext context) {
    final int s = stock ?? 0;
    final hayStock = s > 0;
    final color = hayStock ? Colors.green.shade700 : Colors.red.shade700;
    final texto = hayStock ? 'Stock: $s' : 'Sin stock';
    final icono = hayStock ? Icons.inventory_2_outlined : Icons.block;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            texto,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
