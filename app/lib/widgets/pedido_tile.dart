import 'package:flutter/material.dart';

import '../models/cliente.dart' show EstadoSync;
import '../models/pedido.dart';
import 'chip_estado_sync.dart';

/// Fila de pedido en la lista. Muestra:
/// - Avatar con icono de pedido.
/// - Número Odoo (si está confirmado) o "Borrador" si aún no se subió.
/// - Cliente y fecha como metadatos.
/// - Total destacado a la derecha.
/// - Chip de estado de sincronización (oculto si SINCRONIZADO).
class PedidoTile extends StatelessWidget {
  final Pedido pedido;
  final VoidCallback? onTap;

  const PedidoTile({
    super.key,
    required this.pedido,
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
                child: Icon(
                  Icons.receipt_long,
                  color: scheme.onPrimaryContainer,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pedido.numero ?? 'Borrador',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pedido.clienteNombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _Metadato(
                      icono: Icons.calendar_today,
                      texto: _formatearFecha(pedido.fecha),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatearPrecio(pedido.total),
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ChipEstadoSync(estado: pedido.estadoSync),
                  if (pedido.estadoSync == EstadoSync.sincronizado)
                    Icon(Icons.chevron_right, color: Colors.grey.shade400),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatearFecha(DateTime fecha) {
    String dosDig(int v) => v.toString().padLeft(2, '0');
    return '${dosDig(fecha.day)}/${dosDig(fecha.month)}/${fecha.year}';
  }

  String _formatearPrecio(double valor) {
    final entero = valor.truncate();
    final decimales =
        ((valor - entero) * 100).round().abs().toString().padLeft(2, '0');
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
