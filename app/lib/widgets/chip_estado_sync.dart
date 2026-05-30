import 'package:flutter/material.dart';

import '../models/cliente.dart';

/// Chip compacto que representa el estado de sincronización de un cliente
/// (o cualquier entidad con [EstadoSync]).
///
/// - **SINCRONIZADO**: verde, sin etiqueta visible (chip muy discreto).
/// - **PENDENTE**: ámbar con texto "Pendente".
/// - **ERRO**: rojo con texto "Error".
class ChipEstadoSync extends StatelessWidget {
  final EstadoSync estado;

  /// Si es true (por defecto), oculta el chip cuando el estado es
  /// [EstadoSync.sincronizado] para no añadir ruido visual en la lista.
  final bool ocultarSiSincronizado;

  const ChipEstadoSync({
    super.key,
    required this.estado,
    this.ocultarSiSincronizado = true,
  });

  @override
  Widget build(BuildContext context) {
    if (estado == EstadoSync.sincronizado && ocultarSiSincronizado) {
      return const SizedBox.shrink();
    }

    final (color, texto, icono) = switch (estado) {
      EstadoSync.sincronizado => (Colors.green, 'Sincronizado', Icons.cloud_done),
      EstadoSync.pendente => (Colors.amber.shade700, 'Pendiente', Icons.cloud_upload),
      EstadoSync.erro => (Colors.red.shade700, 'Error', Icons.error_outline),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: color),
          const SizedBox(width: 4),
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
