import 'package:flutter/material.dart';

import '../models/cliente.dart';
import 'chip_estado_sync.dart';

/// Tarjeta de cliente en la lista. Muestra:
/// - Avatar con la inicial del nombre comercial.
/// - Nombre comercial (principal).
/// - CIF y localidad como "metadatos" pequeños con icono.
/// - Razón social en una línea adicional si difiere del nombre comercial.
/// - Chip de estado de sincronización (oculto si SINCRONIZADO).
class ClienteTile extends StatelessWidget {
  final Cliente cliente;
  final VoidCallback? onTap;

  const ClienteTile({
    super.key,
    required this.cliente,
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
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                child: Text(
                  _inicial(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cliente.nombreComercial,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    if (_razonSocialDistinta()) ...[
                      const SizedBox(height: 2),
                      Text(
                        cliente.razonSocial!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    _filaMetadatos(context),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ChipEstadoSync(estado: cliente.estadoSync),
                  if (cliente.estadoSync != EstadoSync.sincronizado)
                    const SizedBox(height: 6),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Fila de metadatos pequeños bajo el título: CIF y localidad si existen.
  Widget _filaMetadatos(BuildContext context) {
    final hayCif = cliente.cif != null && cliente.cif!.isNotEmpty;
    final hayLocalidad =
        cliente.localidad != null && cliente.localidad!.isNotEmpty;
    if (!hayCif && !hayLocalidad) return const SizedBox.shrink();
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        if (hayCif)
          _Metadato(icono: Icons.numbers, texto: cliente.cif!),
        if (hayLocalidad)
          _Metadato(icono: Icons.place_outlined, texto: cliente.localidad!),
      ],
    );
  }

  bool _razonSocialDistinta() {
    final rs = cliente.razonSocial;
    return rs != null && rs.isNotEmpty && rs != cliente.nombreComercial;
  }

  String _inicial() {
    final nombre = cliente.nombreComercial.trim();
    if (nombre.isEmpty) return '?';
    return nombre.substring(0, 1).toUpperCase();
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
