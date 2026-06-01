import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/cliente.dart';
import '../../models/pedido.dart';
import '../../providers/clientes_provider.dart';
import '../../providers/pedidos_provider.dart';
import '../../services/sync_clientes_service.dart';
import '../../services/sync_pedidos_service.dart';
import '../../widgets/dialogo_coincidencias_cif.dart';
import '../clientes/cliente_detalle_screen.dart';
import '../pedidos/pedido_detalle_screen.dart';

/// Pantalla en la que el usuario revisa los clientes y pedidos que aún no
/// se han podido sincronizar con el servidor.
///
/// La pantalla está organizada por **tipo de entidad** (clientes y pedidos)
/// para que el usuario sepa de un vistazo dónde está cada problema. Dentro
/// de cada bloque hay dos subsecciones independientes:
///
/// - **Con error**: filas en estado ERRO.
///   - Para clientes, si el error es un 409 por CIF duplicado, se ofrece
///     un botón para ver las coincidencias y forzar el alta si procede.
///   - Para pedidos, el caso "Esperando a que se sincronice el cliente"
///     se presenta de forma especial, con un atajo para abrir el cliente
///     responsable y resolver primero ese alta.
/// - **Pendientes**: filas que aún no se han intentado subir.
///
/// En ambos casos el usuario puede eliminar localmente la fila si
/// considera que fue un error crearla (siempre que aún no haya `id_servidor`).
class EstadoSyncScreen extends StatefulWidget {
  const EstadoSyncScreen({super.key});

  @override
  State<EstadoSyncScreen> createState() => _EstadoSyncScreenState();
}

class _EstadoSyncScreenState extends State<EstadoSyncScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ClientesProvider>().recargarDesdeLocal();
      context.read<PedidosProvider>().recargarDesdeLocal();
    });
  }

  @override
  Widget build(BuildContext context) {
    final clientesProv = context.watch<ClientesProvider>();
    final pedidosProv = context.watch<PedidosProvider>();

    final clientesError = clientesProv.clientesPorEstado(EstadoSync.erro);
    final clientesPendientes =
        clientesProv.clientesPorEstado(EstadoSync.pendente);
    final pedidosError = pedidosProv.pedidosPorEstado(EstadoSync.erro);
    final pedidosPendientes = pedidosProv.pedidosPorEstado(EstadoSync.pendente);

    final todoAlDia = clientesError.isEmpty &&
        clientesPendientes.isEmpty &&
        pedidosError.isEmpty &&
        pedidosPendientes.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Estado de sincronización'),
      ),
      body: RefreshIndicator(
        onRefresh: _recargarTodo,
        child: todoAlDia
            ? _vistaTodoAlDia(context)
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  if (clientesError.isNotEmpty || clientesPendientes.isNotEmpty)
                    _BloqueEntidad(
                      titulo: 'Clientes',
                      icono: Icons.people,
                      conError: [
                        for (final c in clientesError)
                          _FilaClienteConError(
                              cliente: c, onCambio: _recargarTodo),
                      ],
                      pendientes: [
                        for (final c in clientesPendientes)
                          _FilaClientePendiente(
                              cliente: c, onCambio: _recargarTodo),
                      ],
                    ),
                  if (pedidosError.isNotEmpty || pedidosPendientes.isNotEmpty)
                    _BloqueEntidad(
                      titulo: 'Pedidos',
                      icono: Icons.receipt_long,
                      conError: [
                        for (final p in pedidosError)
                          _FilaPedidoConError(
                              pedido: p, onCambio: _recargarTodo),
                      ],
                      pendientes: [
                        for (final p in pedidosPendientes)
                          _FilaPedidoPendiente(
                              pedido: p, onCambio: _recargarTodo),
                      ],
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _recargarTodo() async {
    if (!mounted) return;
    await Future.wait([
      context.read<ClientesProvider>().recargarDesdeLocal(),
      context.read<PedidosProvider>().recargarDesdeLocal(),
    ]);
  }

  Widget _vistaTodoAlDia(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 96),
        const Icon(Icons.check_circle_outline,
            size: 72, color: Colors.green),
        const SizedBox(height: 16),
        const Text(
          'Todo al día',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'No hay clientes ni pedidos pendientes ni con error.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700),
        ),
      ],
    );
  }
}

// =============================================================================
// Bloque por tipo de entidad (clientes o pedidos)
// =============================================================================

class _BloqueEntidad extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final List<Widget> conError;
  final List<Widget> pendientes;

  const _BloqueEntidad({
    required this.titulo,
    required this.icono,
    required this.conError,
    required this.pendientes,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera del bloque
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Row(
              children: [
                Icon(icono, color: scheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  titulo.toUpperCase(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: scheme.primary,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          if (conError.isNotEmpty) ...[
            _CabeceraSeccion(
              titulo: 'Con error',
              total: conError.length,
              color: Colors.red.shade700,
              icono: Icons.error_outline,
            ),
            ...conError,
            const SizedBox(height: 8),
          ],
          if (pendientes.isNotEmpty) ...[
            _CabeceraSeccion(
              titulo: 'Pendientes de enviar',
              total: pendientes.length,
              color: Colors.amber.shade700,
              icono: Icons.cloud_upload,
            ),
            ...pendientes,
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Cabecera de cada subsección con el total entre paréntesis
// =============================================================================

class _CabeceraSeccion extends StatelessWidget {
  final String titulo;
  final int total;
  final Color color;
  final IconData icono;

  const _CabeceraSeccion({
    required this.titulo,
    required this.total,
    required this.color,
    required this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Icon(icono, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            '$titulo ($total)',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Fila de un cliente con error de sincronización
// =============================================================================

class _FilaClienteConError extends StatefulWidget {
  final Cliente cliente;
  final Future<void> Function() onCambio;

  const _FilaClienteConError({required this.cliente, required this.onCambio});

  @override
  State<_FilaClienteConError> createState() => _FilaClienteConErrorState();
}

class _FilaClienteConErrorState extends State<_FilaClienteConError> {
  bool _trabajando = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.cliente;
    final tieneCoincidencias =
        c.coincidencias409 != null && c.coincidencias409!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cabeceraCliente(c, Colors.red.shade700),
            const SizedBox(height: 8),
            _BloqueMensaje(
              mensaje: c.mensajeError ?? 'Error desconocido',
              icono: Icons.warning_amber_rounded,
              color: Colors.red,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (tieneCoincidencias)
                  FilledButton.tonalIcon(
                    onPressed: _trabajando ? null : _verDuplicadoYResolver,
                    icon: const Icon(Icons.compare_arrows, size: 18),
                    label: const Text('Ver duplicado y resolver'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: _trabajando
                        ? null
                        : () => _reintentar(forzarAlta: false),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reintentar'),
                  ),
                TextButton.icon(
                  onPressed: _trabajando ? null : _eliminarLocal,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Eliminar local'),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _verDuplicadoYResolver() async {
    final coincidencias =
        _parsearCoincidencias(widget.cliente.coincidencias409);
    if (coincidencias.isEmpty) {
      _mostrarSnack(
          'No se pudieron leer las coincidencias guardadas.', esError: true);
      return;
    }
    final confirmar = await DialogoCoincidenciasCif.mostrar(
      context,
      coincidencias: coincidencias,
      cif: widget.cliente.cif ?? '',
      textoConfirmar: 'Crear de todas formas',
    );
    if (!confirmar || !mounted) return;
    await _reintentar(forzarAlta: true);
  }

  Future<void> _reintentar({required bool forzarAlta}) async {
    setState(() => _trabajando = true);
    final resultado = await context
        .read<ClientesProvider>()
        .reintentarCliente(widget.cliente.idLocal, forzarAlta: forzarAlta);
    if (!mounted) return;
    setState(() => _trabajando = false);
    _mostrarResultado(resultado);
    await widget.onCambio();
  }

  Future<void> _eliminarLocal() async {
    final confirmar = await _confirmarEliminarCliente(context, widget.cliente);
    if (!confirmar || !mounted) return;
    try {
      await context
          .read<ClientesProvider>()
          .eliminarClienteLocal(widget.cliente.idLocal);
      if (!mounted) return;
      _mostrarSnack('Cliente eliminado de la base local.');
      await widget.onCambio();
    } on StateError catch (e) {
      _mostrarSnack(e.message, esError: true);
    }
  }

  Widget _cabeceraCliente(Cliente c, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.nombreComercial,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (c.cif != null && c.cif!.isNotEmpty)
                Text(
                  'CIF ${c.cif}',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
            ],
          ),
        ),
        if (_trabajando)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }

  void _mostrarResultado(ResultadoEnvioUno resultado) {
    switch (resultado) {
      case ResultadoEnvioUno.sincronizado:
        _mostrarSnack('Cliente sincronizado con el servidor.', verde: true);
      case ResultadoEnvioUno.duplicado409:
        _mostrarSnack('El servidor sigue marcándolo como duplicado.',
            esError: true);
      case ResultadoEnvioUno.errorRecuperable:
        _mostrarSnack('No se ha podido enviar. Revisa la conexión.',
            esError: true);
      case ResultadoEnvioUno.sesionCaducada:
        _mostrarSnack('Sesión caducada. Vuelve a iniciar sesión.',
            esError: true);
    }
  }

  void _mostrarSnack(String texto, {bool esError = false, bool verde = false}) {
    final scheme = Theme.of(context).colorScheme;
    final bg = esError
        ? scheme.error
        : verde
            ? Colors.green.shade700
            : null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: bg),
    );
  }
}

// =============================================================================
// Fila de un cliente pendiente
// =============================================================================

class _FilaClientePendiente extends StatelessWidget {
  final Cliente cliente;
  final Future<void> Function() onCambio;

  const _FilaClientePendiente({required this.cliente, required this.onCambio});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Colors.amber.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.amber.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_upload, color: Colors.amber.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cliente.nombreComercial,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (cliente.cif != null && cliente.cif!.isNotEmpty)
                        Text(
                          'CIF ${cliente.cif}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade700),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Se enviará en la próxima sincronización.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _eliminar(context),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Eliminar local'),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _eliminar(BuildContext context) async {
    final confirmar = await _confirmarEliminarCliente(context, cliente);
    if (!confirmar || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context
          .read<ClientesProvider>()
          .eliminarClienteLocal(cliente.idLocal);
      messenger.showSnackBar(
        const SnackBar(content: Text('Cliente eliminado de la base local.')),
      );
      await onCambio();
    } on StateError catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

// =============================================================================
// Fila de un pedido con error
// =============================================================================

class _FilaPedidoConError extends StatefulWidget {
  final Pedido pedido;
  final Future<void> Function() onCambio;

  const _FilaPedidoConError({required this.pedido, required this.onCambio});

  @override
  State<_FilaPedidoConError> createState() => _FilaPedidoConErrorState();
}

class _FilaPedidoConErrorState extends State<_FilaPedidoConError> {
  bool _trabajando = false;

  /// Identificamos el caso especial "esperando cliente" por una subcadena
  /// estable del mensaje que escribe el sync service. No es ideal acoplarse
  /// al texto exacto, pero introducir un enum aparte para un único caso
  /// añadiría complejidad sin ganar mucho.
  bool get _esperandoCliente {
    final msg = widget.pedido.mensajeError?.toLowerCase() ?? '';
    return msg.contains('esperando');
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pedido;
    final esperando = _esperandoCliente;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: esperando ? Colors.blue.shade50 : Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: esperando ? Colors.blue.shade200 : Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cabeceraPedido(p,
                color:
                    esperando ? Colors.blue.shade700 : Colors.red.shade700),
            const SizedBox(height: 8),
            _BloqueMensaje(
              mensaje: p.mensajeError ?? 'Error desconocido',
              icono: esperando
                  ? Icons.hourglass_empty
                  : Icons.warning_amber_rounded,
              color: esperando ? Colors.blue : Colors.red,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (esperando)
                  FilledButton.tonalIcon(
                    onPressed: _trabajando ? null : _verCliente,
                    icon: const Icon(Icons.person_search, size: 18),
                    label: const Text('Ver cliente'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: _trabajando ? null : _reintentar,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reintentar'),
                  ),
                TextButton.icon(
                  onPressed: _trabajando ? null : _eliminarLocal,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Eliminar local'),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reintentar() async {
    setState(() => _trabajando = true);
    final resultado = await context
        .read<PedidosProvider>()
        .reintentarPedido(widget.pedido.idLocal);
    if (!mounted) return;
    setState(() => _trabajando = false);
    _mostrarResultadoPedido(resultado);
    await widget.onCambio();
  }

  void _verCliente() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ClienteDetalleScreen(idLocal: widget.pedido.clienteIdLocal),
      ),
    );
  }

  Future<void> _eliminarLocal() async {
    final confirmar = await _confirmarEliminarPedido(context, widget.pedido);
    if (!confirmar || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await context
        .read<PedidosProvider>()
        .eliminarPedidoLocal(widget.pedido.idLocal);
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Pedido eliminado de la base local.')),
      );
      await widget.onCambio();
    } else {
      messenger.showSnackBar(
        const SnackBar(
            content: Text(
                'No se pudo eliminar: el pedido ya está sincronizado con el servidor.')),
      );
    }
  }

  Widget _cabeceraPedido(Pedido p, {required Color color}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.receipt_long, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.numero ?? 'Pedido borrador',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15),
              ),
              Text(
                p.clienteNombre,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (_trabajando)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          IconButton(
            icon: const Icon(Icons.open_in_new, size: 18),
            tooltip: 'Abrir detalle',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      PedidoDetalleScreen(idLocal: widget.pedido.idLocal),
                ),
              );
            },
          ),
      ],
    );
  }

  void _mostrarResultadoPedido(ResultadoEnvioPedido resultado) {
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    switch (resultado) {
      case ResultadoEnvioPedido.sincronizado:
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Pedido enviado al servidor.'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      case ResultadoEnvioPedido.esperandoCliente:
        messenger.showSnackBar(
          const SnackBar(
              content: Text(
                  'El cliente sigue sin sincronizar — sube primero al cliente.')),
        );
      case ResultadoEnvioPedido.errorRecuperable:
        messenger.showSnackBar(
          SnackBar(
            content:
                const Text('No se ha podido enviar. Revisa la conexión.'),
            backgroundColor: scheme.error,
          ),
        );
      case ResultadoEnvioPedido.sesionCaducada:
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Sesión caducada. Vuelve a iniciar sesión.'),
            backgroundColor: scheme.error,
          ),
        );
    }
  }
}

// =============================================================================
// Fila de un pedido pendiente
// =============================================================================

class _FilaPedidoPendiente extends StatelessWidget {
  final Pedido pedido;
  final Future<void> Function() onCambio;

  const _FilaPedidoPendiente({required this.pedido, required this.onCambio});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Colors.amber.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.amber.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_upload, color: Colors.amber.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pedido.numero ?? 'Pedido borrador',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      Text(
                        pedido.clienteNombre,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  tooltip: 'Abrir detalle',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PedidoDetalleScreen(idLocal: pedido.idLocal),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Se enviará en la próxima sincronización.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _eliminar(context),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Eliminar local'),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _eliminar(BuildContext context) async {
    // Capturamos las referencias que dependen del context ANTES de awaits
    // (el lint use_build_context_synchronously no acepta context.mounted
    // como guard suficiente para context.read).
    final pedidosProv = context.read<PedidosProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmar = await _confirmarEliminarPedido(context, pedido);
    if (!confirmar) return;
    final ok = await pedidosProv.eliminarPedidoLocal(pedido.idLocal);
    if (ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Pedido eliminado de la base local.')),
      );
      await onCambio();
    } else {
      messenger.showSnackBar(
        const SnackBar(
            content: Text(
                'No se pudo eliminar: el pedido ya está sincronizado con el servidor.')),
      );
    }
  }
}

// =============================================================================
// Helpers compartidos
// =============================================================================

/// Recuadro con el icono y el mensaje de error. Comparte estilo entre filas
/// de cliente y de pedido para que el aviso sea visualmente reconocible.
class _BloqueMensaje extends StatelessWidget {
  final String mensaje;
  final IconData icono;
  final MaterialColor color;

  const _BloqueMensaje({
    required this.mensaje,
    required this.icono,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icono, size: 16, color: color.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(fontSize: 13, color: color.shade900),
            ),
          ),
        ],
      ),
    );
  }
}

/// Convierte el JSON de coincidencias 409 en una lista de [Cliente] para
/// visualizar (nunca se persisten).
List<Cliente> _parsearCoincidencias(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final lista = jsonDecode(json) as List;
    return lista
        .cast<Map<String, dynamic>>()
        .map((j) => Cliente.desdeServidor(
              j,
              idLocal: 'srv-${j['id']}',
            ))
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

Future<bool> _confirmarEliminarCliente(
    BuildContext context, Cliente cliente) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Eliminar cliente'),
      content: Text(
        '¿Seguro que quiere eliminar "${cliente.nombreComercial}"? '
        'Esta acción no se puede deshacer.',
        textAlign: TextAlign.center,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(foregroundColor: Colors.red.shade700),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

Future<bool> _confirmarEliminarPedido(
    BuildContext context, Pedido pedido) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Eliminar pedido'),
      content: Text(
        '¿Seguro que quiere eliminar el pedido de "${pedido.clienteNombre}"? '
        'Esta acción no se puede deshacer.',
        textAlign: TextAlign.center,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(foregroundColor: Colors.red.shade700),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
