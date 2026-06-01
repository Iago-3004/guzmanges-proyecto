import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/cliente.dart' show EstadoSync;
import '../../models/pedido.dart';
import '../../providers/pedidos_provider.dart';
import '../../widgets/chip_estado_sync.dart';
import 'pedido_form_screen.dart';

/// Vista de solo lectura con el detalle de un pedido. Si todavía está en
/// BORRADOR + PENDENTE (no se ha subido al servidor), ofrece un botón para
/// eliminarlo en local. Los pedidos ya subidos solo se pueden ver, nunca
/// editar: la fuente de verdad pasa a ser el servidor / Odoo.
class PedidoDetalleScreen extends StatefulWidget {
  final String idLocal;

  const PedidoDetalleScreen({super.key, required this.idLocal});

  @override
  State<PedidoDetalleScreen> createState() => _PedidoDetalleScreenState();
}

class _PedidoDetalleScreenState extends State<PedidoDetalleScreen> {
  Pedido? _pedido;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final p = await context.read<PedidosProvider>().obtener(widget.idLocal);
    if (!mounted) return;
    setState(() {
      _pedido = p;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pedido')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final pedido = _pedido;
    if (pedido == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pedido')),
        body: const Center(child: Text('Pedido no encontrado')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(pedido.numero ?? 'Pedido borrador'),
        actions: [
          if (_puedeEditar(pedido))
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar pedido',
              onPressed: () => _editar(pedido),
            ),
          if (_puedeEliminar(pedido))
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Eliminar borrador',
              onPressed: () => _confirmarEliminar(pedido),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _Cabecera(pedido: pedido),
          const SizedBox(height: 16),
          if (pedido.estadoSync == EstadoSync.erro &&
              pedido.mensajeError != null) ...[
            _TarjetaError(mensaje: pedido.mensajeError!),
            const SizedBox(height: 12),
          ],
          _SeccionLineas(lineas: pedido.lineas),
          if (pedido.observaciones != null &&
              pedido.observaciones!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SeccionObservaciones(texto: pedido.observaciones!),
          ],
          const SizedBox(height: 12),
          _SeccionTotales(pedido: pedido),
          if (pedido.idServidor == null) ...[
            const SizedBox(height: 16),
            _avisoProvisional(),
          ],
        ],
      ),
    );
  }

  Widget _avisoProvisional() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Totales provisionales. Al confirmarse en Odoo se aplica la '
            'posición fiscal del cliente y se reescriben con los definitivos.',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  bool _puedeEliminar(Pedido p) {
    return p.estadoPedido == EstadoPedido.borrador && p.idServidor == null;
  }

  /// Editable: pedido en BORRADOR que aún no se subió al servidor. Cubre
  /// tanto los PENDENTE (esperando a la próxima sincronización) como los
  /// ERRO (el último intento falló: corregir y reintentar). Una vez el
  /// servidor le asigna id, la fuente de verdad es Odoo y la app no toca.
  bool _puedeEditar(Pedido p) {
    return p.estadoPedido == EstadoPedido.borrador && p.idServidor == null;
  }

  Future<void> _editar(Pedido p) async {
    final cambiado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PedidoFormScreen(idLocalEditar: p.idLocal),
      ),
    );
    if (cambiado == true && mounted) {
      await _cargar();
    }
  }

  Future<void> _confirmarEliminar(Pedido p) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar borrador'),
        content: const Text(
            'El pedido se borrará del dispositivo. Como aún no se ha enviado al servidor, no quedará rastro de él. ¿Continuar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    final ok = await context
        .read<PedidosProvider>()
        .eliminarPedidoLocal(p.idLocal);
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Borrador eliminado')),
      );
      navigator.pop();
    } else {
      messenger.showSnackBar(
        const SnackBar(
            content: Text(
                'No se pudo eliminar: el pedido ya está sincronizado con el servidor')),
      );
    }
  }
}

// =============================================================================
// Cabecera con número, fecha, cliente y estado
// =============================================================================

class _Cabecera extends StatelessWidget {
  final Pedido pedido;

  const _Cabecera({required this.pedido});

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                child: Icon(
                  Icons.receipt_long,
                  color: scheme.onPrimary,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pedido.numero ?? 'Pedido borrador',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.onPrimaryContainer,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _ChipEstadoPedido(estado: pedido.estadoPedido),
                        const SizedBox(width: 6),
                        ChipEstadoSync(
                          estado: pedido.estadoSync,
                          ocultarSiSincronizado: false,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _filaInfo(
            icono: Icons.person_outline,
            etiqueta: 'Cliente',
            valor: pedido.clienteNombre,
            scheme: scheme,
          ),
          const SizedBox(height: 6),
          _filaInfo(
            icono: Icons.calendar_today,
            etiqueta: 'Fecha',
            valor: _formatearFecha(pedido.fecha),
            scheme: scheme,
          ),
        ],
      ),
    );
  }

  Widget _filaInfo({
    required IconData icono,
    required String etiqueta,
    required String valor,
    required ColorScheme scheme,
  }) {
    return Row(
      children: [
        Icon(icono, size: 16, color: scheme.onPrimaryContainer),
        const SizedBox(width: 8),
        Text(
          '$etiqueta: ',
          style: TextStyle(
            color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
            fontSize: 13,
          ),
        ),
        Expanded(
          child: Text(
            valor,
            style: TextStyle(
              color: scheme.onPrimaryContainer,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatearFecha(DateTime fecha) {
    String dos(int v) => v.toString().padLeft(2, '0');
    return '${dos(fecha.day)}/${dos(fecha.month)}/${fecha.year} '
        '${dos(fecha.hour)}:${dos(fecha.minute)}';
  }
}

class _ChipEstadoPedido extends StatelessWidget {
  final EstadoPedido estado;

  const _ChipEstadoPedido({required this.estado});

  @override
  Widget build(BuildContext context) {
    final (color, texto) = switch (estado) {
      EstadoPedido.borrador => (Colors.grey.shade700, 'Borrador'),
      EstadoPedido.confirmado => (Colors.green.shade700, 'Confirmado'),
      EstadoPedido.anulado => (Colors.red.shade700, 'Anulado'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// =============================================================================
// Aviso de error de sincronización
// =============================================================================

class _TarjetaError extends StatelessWidget {
  final String mensaje;

  const _TarjetaError({required this.mensaje});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.shade50,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Error al sincronizar',
                    style: TextStyle(
                      color: Colors.red.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mensaje,
                    style: TextStyle(color: Colors.red.shade800),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Líneas
// =============================================================================

class _SeccionLineas extends StatelessWidget {
  final List lineas;

  const _SeccionLineas({required this.lineas});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.list_alt, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'LÍNEAS (${lineas.length})',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            for (int i = 0; i < lineas.length; i++) ...[
              _FilaLinea(linea: lineas[i]),
              if (i < lineas.length - 1) const Divider(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilaLinea extends StatelessWidget {
  final dynamic linea; // LineaPedido (sin import explícito por concisión)

  const _FilaLinea({required this.linea});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  linea.descripcion as String,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _detalles(),
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatearPrecio(linea.subtotal as double),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  String _detalles() {
    final cant = linea.cantidade;
    final precio = _formatearPrecio(linea.precio as double);
    final iva = _porcentaje(linea.iva as double);
    final re = linea.recargoEquivalencia as double;
    final partes = ['$cant × $precio', 'IVA $iva%'];
    if (re > 0) partes.add('RE ${_porcentaje(re)}%');
    return partes.join(' · ');
  }

  String _porcentaje(double v) {
    if (v == v.truncate()) return v.truncate().toString();
    return v
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
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

// =============================================================================
// Observaciones (nota del pedido)
// =============================================================================

/// Bloque que muestra las observaciones del pedido si las hay. Se renderiza
/// entre las líneas y los totales, replicando el orden en el que aparecen
/// las notas en el PDF de Odoo (después de las líneas).
class _SeccionObservaciones extends StatelessWidget {
  final String texto;

  const _SeccionObservaciones({required this.texto});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.note_alt_outlined,
                    color: scheme.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'OBSERVACIONES',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              texto,
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Totales
// =============================================================================

class _SeccionTotales extends StatelessWidget {
  final Pedido pedido;

  const _SeccionTotales({required this.pedido});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      color: scheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TOTALES',
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            _fila('Base imponible', pedido.totalBase),
            _fila('IVA', pedido.totalIva),
            if (pedido.totalRE > 0) _fila('Recargo equivalencia', pedido.totalRE),
            const Divider(height: 20),
            _fila('Total', pedido.total, destacar: true),
          ],
        ),
      ),
    );
  }

  Widget _fila(String etiqueta, double valor, {bool destacar = false}) {
    final estilo = destacar
        ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
        : const TextStyle(fontSize: 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(etiqueta, style: estilo)),
          Text(_formatearPrecio(valor), style: estilo),
        ],
      ),
    );
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
