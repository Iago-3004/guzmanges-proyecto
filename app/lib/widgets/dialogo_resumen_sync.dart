import 'package:flutter/material.dart';

import '../providers/sync_provider.dart';

/// Diálogo que muestra el resumen detallado de una sincronización: lo que
/// se descargó, lo que se subió y lo que quedó con error.
///
/// Sustituye al SnackBar de "Sincronización completada · ..." que se queda
/// corto ahora que el resumen incluye clientes y pedidos en los dos
/// sentidos. Aquí cada cifra se ve en su línea y, si hay errores, se ofrece
/// un botón para saltar directamente a la pantalla de estado.
class DialogoResumenSync extends StatelessWidget {
  final ResultadoSincronizacion resultado;
  final VoidCallback? onVerEstado;

  const DialogoResumenSync({
    super.key,
    required this.resultado,
    this.onVerEstado,
  });

  static Future<void> mostrar(
    BuildContext context, {
    required ResultadoSincronizacion resultado,
    VoidCallback? onVerEstado,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => DialogoResumenSync(
        resultado: resultado,
        onVerEstado: onVerEstado,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hayError = resultado.hayErrores;
    final color = hayError ? Colors.amber.shade700 : Colors.green.shade700;
    final icono =
        hayError ? Icons.warning_amber_rounded : Icons.check_circle_outline;
    final titulo =
        hayError ? 'Sincronización con avisos' : 'Sincronización completada';

    return AlertDialog(
      icon: Icon(icono, color: color, size: 44),
      title: Text(titulo, textAlign: TextAlign.center),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _seccionDescargado(),
              const SizedBox(height: 12),
              _seccionEnviado(),
              if (hayError) ...[
                const SizedBox(height: 12),
                _seccionErrores(),
              ],
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        if (hayError && onVerEstado != null)
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              onVerEstado!();
            },
            icon: const Icon(Icons.sync_problem, size: 18),
            label: const Text('Ver estado'),
          )
        else
          const SizedBox.shrink(),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Aceptar'),
        ),
      ],
    );
  }

  // =========================================================================
  // Bloques por categoría
  // =========================================================================

  Widget _seccionDescargado() {
    final filas = <_FilaResumen>[
      if (resultado.modos > 0 || resultado.condiciones > 0)
        _FilaResumen(
          icono: Icons.payments_outlined,
          etiqueta: 'Catálogos',
          valor:
              '${resultado.modos} modos · ${resultado.condiciones} condiciones',
        ),
      if (resultado.productosBajados > 0)
        _FilaResumen(
          icono: Icons.inventory_2_outlined,
          etiqueta: 'Productos descargados',
          valor: '${resultado.productosBajados}',
        ),
      if (resultado.clientesBajados > 0)
        _FilaResumen(
          icono: Icons.people_outline,
          etiqueta: 'Clientes descargados',
          valor: '${resultado.clientesBajados}',
        ),
      if (resultado.pedidosBajados > 0)
        _FilaResumen(
          icono: Icons.receipt_long_outlined,
          etiqueta: 'Pedidos descargados',
          valor: '${resultado.pedidosBajados}',
        ),
    ];
    return _Bloque(
      titulo: 'Descargado del servidor',
      color: Colors.blue.shade700,
      filas: filas,
    );
  }

  Widget _seccionEnviado() {
    final filas = <_FilaResumen>[
      _FilaResumen(
        icono: Icons.cloud_upload_outlined,
        etiqueta: 'Clientes enviados',
        valor: '${resultado.clientesSubidos}',
      ),
      _FilaResumen(
        icono: Icons.cloud_upload_outlined,
        etiqueta: 'Pedidos enviados',
        valor: '${resultado.pedidosSubidos}',
      ),
    ];
    return _Bloque(
      titulo: 'Enviado al servidor',
      color: Colors.green.shade700,
      filas: filas,
    );
  }

  Widget _seccionErrores() {
    final filas = <_FilaResumen>[
      if (resultado.clientesConError > 0)
        _FilaResumen(
          icono: Icons.error_outline,
          etiqueta: 'Clientes con error',
          valor: '${resultado.clientesConError}',
          colorValor: Colors.red.shade700,
        ),
      if (resultado.pedidosConError > 0)
        _FilaResumen(
          icono: Icons.error_outline,
          etiqueta: 'Pedidos con error',
          valor: '${resultado.pedidosConError}'
              '${resultado.pedidosEsperandoCliente > 0
                  ? ' (${resultado.pedidosEsperandoCliente} esperando cliente)'
                  : ''}',
          colorValor: Colors.red.shade700,
        ),
    ];
    return _Bloque(
      titulo: 'Necesita tu revisión',
      color: Colors.red.shade700,
      filas: filas,
    );
  }
}

// =============================================================================
// Bloque con cabecera de color, filas y separación visual
// =============================================================================

class _Bloque extends StatelessWidget {
  final String titulo;
  final Color color;
  final List<_FilaResumen> filas;

  const _Bloque({
    required this.titulo,
    required this.color,
    required this.filas,
  });

  @override
  Widget build(BuildContext context) {
    if (filas.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo.toUpperCase(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          ...filas,
        ],
      ),
    );
  }
}

class _FilaResumen extends StatelessWidget {
  final IconData icono;
  final String etiqueta;
  final String valor;
  final Color? colorValor;

  const _FilaResumen({
    required this.icono,
    required this.etiqueta,
    required this.valor,
    this.colorValor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icono, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              etiqueta,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            valor,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: colorValor,
            ),
          ),
        ],
      ),
    );
  }
}
