import 'package:flutter/material.dart';

import '../models/cliente.dart';
import 'chip_estado_sync.dart';

/// Diálogo que muestra la lista de clientes existentes que coinciden con un
/// CIF dado, y deja al usuario decidir si crear el alta igualmente o
/// cancelar.
///
/// Está diseñado para que sirva tanto cuando las coincidencias se detectan
/// en local como cuando las devuelve el servidor en un 409 — solo cambia el
/// texto del botón de confirmación (ver [textoConfirmar]).
///
/// Devuelve `true` si el usuario decide forzar el alta, `false` si cancela.
class DialogoCoincidenciasCif extends StatelessWidget {
  /// Lista de clientes que coinciden con el CIF.
  final List<Cliente> coincidencias;

  /// CIF que se está intentando dar de alta. Se muestra en la cabecera del
  /// diálogo para que el usuario lo confirme visualmente.
  final String cif;

  /// Texto del botón de confirmación. Útil para adaptar el matiz según el
  /// escenario: p. ej. "Crear de todas formas" cuando el duplicado se
  /// detecta en local, "Forzar alta" cuando lo devuelve el servidor.
  final String textoConfirmar;

  const DialogoCoincidenciasCif({
    super.key,
    required this.coincidencias,
    required this.cif,
    this.textoConfirmar = 'Crear de todas formas',
  });

  /// Helper para mostrar el diálogo y obtener directamente el resultado
  /// (true = confirmar, false = cancelar).
  static Future<bool> mostrar(
    BuildContext context, {
    required List<Cliente> coincidencias,
    required String cif,
    String textoConfirmar = 'Crear de todas formas',
  }) async {
    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DialogoCoincidenciasCif(
        coincidencias: coincidencias,
        cif: cif,
        textoConfirmar: textoConfirmar,
      ),
    );
    return resultado ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded,
          color: Colors.amber.shade700, size: 36),
      title: const Text('CIF duplicado'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ya existen ${coincidencias.length} '
              '${coincidencias.length == 1 ? "cliente" : "clientes"} '
              'con el CIF $cif:',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < coincidencias.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _filaCoincidencia(context, coincidencias[i]),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Solo crea el nuevo cliente si estás seguro de que se trata '
                'de una empresa distinta con el mismo CIF.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(textoConfirmar),
        ),
      ],
    );
  }

  Widget _filaCoincidencia(BuildContext context, Cliente c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.nombreComercial,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (c.localidad != null && c.localidad!.isNotEmpty)
                  Text(
                    c.localidad!,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ChipEstadoSync(
            estado: c.estadoSync,
            ocultarSiSincronizado: false,
          ),
        ],
      ),
    );
  }
}
