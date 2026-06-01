import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/db/dao/clientes_dao.dart';
import '../../core/db/dao/productos_dao.dart';
import '../../core/impuestos/calculadora_re.dart';
import '../../models/cliente.dart';
import '../../models/producto.dart';
import '../../providers/pedidos_provider.dart';
import '../../widgets/selector_cliente_dialogo.dart';
import '../../widgets/selector_producto_dialogo.dart';

/// Alta de un pedido nuevo. Estructura:
///
/// 1. Selector de cliente. Mientras no se elige, no se puede añadir líneas.
/// 2. Lista dinámica de líneas: producto + cantidad (precio, IVA y RE se
///    autocompletan del producto y de la posición fiscal del cliente).
/// 3. Tarjeta de totales en vivo (base + IVA + RE = total) recalculados en
///    Dart como previsualización; el cálculo definitivo lo hace Odoo al
///    confirmar el pedido.
/// 4. Botón "Guardar pedido" → llama a [PedidosProvider.crearPedidoLocal],
///    que persiste e intenta enviar inmediatamente al servidor.
class PedidoFormScreen extends StatefulWidget {
  const PedidoFormScreen({super.key});

  @override
  State<PedidoFormScreen> createState() => _PedidoFormScreenState();
}

class _PedidoFormScreenState extends State<PedidoFormScreen> {
  Cliente? _cliente;
  final List<_LineaEditor> _lineas = [];

  /// Caches de los selectores: clientes y productos en local. Se cargan
  /// una vez al entrar a la pantalla para que abrir los modales sea
  /// instantáneo. Si se sincroniza desde otra pantalla mientras esta está
  /// abierta no se reflejan los cambios — es aceptable: el alta es un
  /// flujo corto.
  List<Cliente> _clientesLocales = const [];
  List<Producto> _productosLocales = const [];
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarCaches();
  }

  Future<void> _cargarCaches() async {
    final clientes = await ClientesDao().listar();
    final productos = await ProductosDao().listar();
    if (!mounted) return;
    setState(() {
      _clientesLocales = clientes;
      _productosLocales = productos;
    });
  }

  @override
  void dispose() {
    for (final l in _lineas) {
      l.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totales = _calcularTotales();
    final puedeGuardar = _cliente != null &&
        _lineas.isNotEmpty &&
        _lineas.every((l) => l.cantidade > 0) &&
        !_guardando;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo pedido'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _SeccionCliente(
            cliente: _cliente,
            onSeleccionar: _seleccionarCliente,
          ),
          const SizedBox(height: 20),
          _SeccionLineas(
            lineas: _lineas,
            puedeAnadir: _cliente != null,
            onAnadir: _anadirLinea,
            onEliminar: _eliminarLinea,
            onCantidadCambiada: _onCantidadCambiada,
          ),
          const SizedBox(height: 20),
          _TarjetaTotales(totales: totales),
          const SizedBox(height: 16),
          _avisoProvisional(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: puedeGuardar ? _guardar : null,
            icon: _guardando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save),
            label: Text(_guardando ? 'Guardando…' : 'Guardar pedido'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
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
            'Los totales son provisionales. Al confirmar el pedido en Odoo se '
            'aplica la posición fiscal del cliente y los importes pueden '
            'variar (recargo de equivalencia, exenciones, etc.).',
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

  Future<void> _seleccionarCliente() async {
    final elegido = await SelectorClienteDialogo.mostrar(
      context,
      clientes: _clientesLocales,
    );
    if (elegido == null) return;
    setState(() {
      _cliente = elegido;
      // Si cambia el cliente y ya hay líneas, recalculamos el RE de cada
      // una según el nuevo régimen (puede pasar de aplicar a no aplicar).
      for (final l in _lineas) {
        l.recargo = _recargoPara(l.iva);
      }
    });
  }

  Future<void> _anadirLinea() async {
    final producto = await SelectorProductoDialogo.mostrar(
      context,
      productos: _productosLocales,
    );
    if (producto == null) return;
    setState(() {
      final iva = producto.iva ?? 0.0;
      _lineas.add(_LineaEditor(
        producto: producto,
        precio: producto.precioVenta ?? 0.0,
        iva: iva,
        recargo: _recargoPara(iva),
        cantidade: 1,
      ));
    });
  }

  void _eliminarLinea(int index) {
    setState(() {
      _lineas.removeAt(index).dispose();
    });
  }

  void _onCantidadCambiada(int index, int nueva) {
    setState(() {
      _lineas[index].cantidade = nueva;
    });
  }

  double _recargoPara(double iva) {
    if (_cliente?.recargoEquivalencia != true) return 0.0;
    return CalculadoraRE.recargoParaIva(iva);
  }

  _Totales _calcularTotales() {
    double base = 0;
    double iva = 0;
    double re = 0;
    for (final l in _lineas) {
      final b = l.precio * l.cantidade;
      base += b;
      iva += b * l.iva / 100;
      re += b * l.recargo / 100;
    }
    return _Totales(
      base: base,
      iva: iva,
      re: re,
      total: base + iva + re,
    );
  }

  Future<void> _guardar() async {
    if (_cliente == null || _lineas.isEmpty) return;
    setState(() => _guardando = true);

    final provider = context.read<PedidosProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await provider.crearPedidoLocal(
        cliente: _cliente!,
        lineas: _lineas
            .map((l) => BorradorLinea(
                  productoId: l.producto.id,
                  codigoProducto: l.producto.referencia,
                  descripcion: l.producto.descripcion,
                  precio: l.precio,
                  iva: l.iva,
                  recargoEquivalencia: l.recargo,
                  cantidade: l.cantidade,
                ))
            .toList(),
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: const Text(
              'Pedido guardado. Se enviará al servidor al sincronizar'),
        ),
      );
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text(
              'Error al guardar: ${e.toString().replaceFirst('Exception: ', '')}'),
        ),
      );
    }
  }
}

// =============================================================================
// Estado mutable de una línea durante la edición del formulario
// =============================================================================

class _LineaEditor {
  final Producto producto;
  final double precio;
  final double iva;
  double recargo;
  int cantidade;
  final TextEditingController cantidadCtrl;

  _LineaEditor({
    required this.producto,
    required this.precio,
    required this.iva,
    required this.recargo,
    required this.cantidade,
  }) : cantidadCtrl = TextEditingController(text: cantidade.toString());

  double get subtotal {
    final base = precio * cantidade;
    return base * (1 + iva / 100 + recargo / 100);
  }

  void dispose() {
    cantidadCtrl.dispose();
  }
}

// =============================================================================
// Secciones de la pantalla
// =============================================================================

class _SeccionCliente extends StatelessWidget {
  final Cliente? cliente;
  final VoidCallback onSeleccionar;

  const _SeccionCliente({
    required this.cliente,
    required this.onSeleccionar,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      child: InkWell(
        onTap: onSeleccionar,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                child: const Icon(Icons.person),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cliente',
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cliente?.nombreComercial ?? 'Seleccionar cliente…',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: cliente == null
                            ? Colors.grey.shade600
                            : null,
                      ),
                    ),
                    if (cliente?.posicionFiscal != null &&
                        cliente!.posicionFiscal!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Posición fiscal: ${cliente!.posicionFiscal}',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeccionLineas extends StatelessWidget {
  final List<_LineaEditor> lineas;
  final bool puedeAnadir;
  final VoidCallback onAnadir;
  final void Function(int) onEliminar;
  final void Function(int, int) onCantidadCambiada;

  const _SeccionLineas({
    required this.lineas,
    required this.puedeAnadir,
    required this.onAnadir,
    required this.onEliminar,
    required this.onCantidadCambiada,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.list_alt, color: scheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'LÍNEAS',
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
        if (lineas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                puedeAnadir
                    ? 'Pulsa "Añadir línea" para empezar.'
                    : 'Selecciona primero un cliente.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          )
        else
          ...List.generate(lineas.length, (i) {
            return _TarjetaLinea(
              linea: lineas[i],
              onEliminar: () => onEliminar(i),
              onCantidadCambiada: (n) => onCantidadCambiada(i, n),
            );
          }),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: puedeAnadir ? onAnadir : null,
            icon: const Icon(Icons.add),
            label: const Text('Añadir línea'),
          ),
        ),
      ],
    );
  }
}

class _TarjetaLinea extends StatelessWidget {
  final _LineaEditor linea;
  final VoidCallback onEliminar;
  final void Function(int) onCantidadCambiada;

  const _TarjetaLinea({
    required this.linea,
    required this.onEliminar,
    required this.onCantidadCambiada,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    linea.producto.descripcion,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _detallesLinea(),
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 72,
              child: TextField(
                controller: linea.cantidadCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Cant.',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
                onChanged: (v) {
                  final n = int.tryParse(v) ?? 0;
                  onCantidadCambiada(n);
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: Colors.red.shade600,
              onPressed: onEliminar,
              tooltip: 'Eliminar línea',
            ),
          ],
        ),
      ),
    );
  }

  String _detallesLinea() {
    final partes = <String>[
      '${_formatearPrecio(linea.precio)} / ud',
      'IVA ${_porcentaje(linea.iva)}%',
    ];
    if (linea.recargo > 0) {
      partes.add('RE ${_porcentaje(linea.recargo)}%');
    }
    partes.add('Subtotal: ${_formatearPrecio(linea.subtotal)}');
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

class _TarjetaTotales extends StatelessWidget {
  final _Totales totales;

  const _TarjetaTotales({required this.totales});

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
              'TOTALES (previsualización)',
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            _filaTotal('Base imponible', totales.base),
            _filaTotal('IVA', totales.iva),
            if (totales.re > 0) _filaTotal('Recargo equivalencia', totales.re),
            const Divider(height: 20),
            _filaTotal('Total', totales.total, destacar: true),
          ],
        ),
      ),
    );
  }

  Widget _filaTotal(String etiqueta, double valor, {bool destacar = false}) {
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

class _Totales {
  final double base;
  final double iva;
  final double re;
  final double total;
  const _Totales({
    required this.base,
    required this.iva,
    required this.re,
    required this.total,
  });
}
