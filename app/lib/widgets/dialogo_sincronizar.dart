import 'package:flutter/material.dart';

/// Diálogo que ofrece sincronizar los datos justo después de iniciar
/// sesión. Devuelve `true` si el usuario acepta, `false` si pospone.
class DialogoSincronizar extends StatelessWidget {
  const DialogoSincronizar({super.key});

  /// Muestra el diálogo y devuelve directamente el resultado.
  static Future<bool> mostrar(BuildContext context) async {
    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const DialogoSincronizar(),
    );
    return resultado ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.cloud_sync_outlined, size: 40, color: scheme.primary),
      title: const Text('Sincronizar datos'),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: const Text(
        '¿Quieres sincronizar ahora con el servidor para tener clientes, '
        'productos y pedidos al día?',
        textAlign: TextAlign.center,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Después'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.sync),
          label: const Text('Sincronizar'),
        ),
      ],
    );
  }
}
