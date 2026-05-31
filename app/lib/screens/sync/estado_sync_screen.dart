import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/cliente.dart';
import '../../providers/clientes_provider.dart';
import '../../services/sync_clientes_service.dart';
import '../../widgets/dialogo_coincidencias_cif.dart';

/// Pantalla en la que el usuario revisa los clientes que aún no se han
/// podido sincronizar con el servidor.
///
/// Tiene dos secciones independientes:
///
/// - **Con error**: clientes en estado ERRO. Si el error es un 409 por CIF
///   duplicado, se ofrece un botón para ver las coincidencias que devolvió
///   el servidor y decidir si forzar el alta. Si es un error de red u otro,
///   solo se ofrece reintentar.
/// - **Pendientes**: clientes que aún no se han intentado subir (creados
///   localmente y a la espera de la próxima sincronización general).
///
/// En ambos casos el usuario puede **eliminar localmente** la fila si
/// considera que fue un error crearla.
class EstadoSyncScreen extends StatefulWidget {
  const EstadoSyncScreen({super.key});

  @override
  State<EstadoSyncScreen> createState() => _EstadoSyncScreenState();
}

class _EstadoSyncScreenState extends State<EstadoSyncScreen> {
  @override
  void initState() {
    super.initState();
    // Refresca por si hay cambios desde otra pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ClientesProvider>().recargarDesdeLocal();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ClientesProvider>();
    final conError = provider.clientesPorEstado(EstadoSync.erro);
    final pendientes = provider.clientesPorEstado(EstadoSync.pendente);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Estado de sincronización'),
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<ClientesProvider>().recargarDesdeLocal(),
        child: (conError.isEmpty && pendientes.isEmpty)
            ? _vistaTodoAlDia(context)
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  if (conError.isNotEmpty) ...[
                    _CabeceraSeccion(
                      titulo: 'Con error',
                      total: conError.length,
                      color: Colors.red.shade700,
                      icono: Icons.error_outline,
                    ),
                    for (final c in conError)
                      _FilaConError(cliente: c, onCambio: _recargar),
                    const SizedBox(height: 8),
                  ],
                  if (pendientes.isNotEmpty) ...[
                    _CabeceraSeccion(
                      titulo: 'Pendientes de enviar',
                      total: pendientes.length,
                      color: Colors.amber.shade700,
                      icono: Icons.cloud_upload,
                    ),
                    for (final c in pendientes)
                      _FilaPendiente(cliente: c, onCambio: _recargar),
                  ],
                ],
              ),
      ),
    );
  }

  void _recargar() {
    if (!mounted) return;
    context.read<ClientesProvider>().recargarDesdeLocal();
  }

  // Mensaje cuando no hay nada que revisar (todo está sincronizado).
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
          'No hay clientes pendientes ni con error.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700),
        ),
      ],
    );
  }
}

// =============================================================================
// Cabecera de cada sección con el total entre paréntesis
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

class _FilaConError extends StatefulWidget {
  final Cliente cliente;
  final VoidCallback onCambio;

  const _FilaConError({required this.cliente, required this.onCambio});

  @override
  State<_FilaConError> createState() => _FilaConErrorState();
}

class _FilaConErrorState extends State<_FilaConError> {
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c.mensajeError ?? 'Error desconocido',
                      style: TextStyle(
                          fontSize: 13, color: Colors.red.shade900),
                    ),
                  ),
                ],
              ),
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
                    onPressed: _trabajando ? null : () => _reintentar(forzarAlta: false),
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

  /// Parsea las coincidencias devueltas por el servidor en el último 409 y
  /// abre el [DialogoCoincidenciasCif]. Si el usuario confirma, reenvía con
  /// `?forzarAlta=true`.
  Future<void> _verDuplicadoYResolver() async {
    final coincidencias = _parsearCoincidencias(widget.cliente.coincidencias409);
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

  /// Reenvía el cliente al servidor. Si [forzarAlta] es true, añade
  /// `?forzarAlta=true` para superar un duplicado ya revisado.
  Future<void> _reintentar({required bool forzarAlta}) async {
    setState(() => _trabajando = true);
    final resultado = await context
        .read<ClientesProvider>()
        .reintentarCliente(widget.cliente.idLocal, forzarAlta: forzarAlta);
    if (!mounted) return;
    setState(() => _trabajando = false);
    _mostrarResultado(resultado);
    widget.onCambio();
  }

  Future<void> _eliminarLocal() async {
    final confirmar = await _confirmarEliminar(context, widget.cliente);
    if (!confirmar || !mounted) return;
    try {
      await context
          .read<ClientesProvider>()
          .eliminarClienteLocal(widget.cliente.idLocal);
      if (!mounted) return;
      _mostrarSnack('Cliente eliminado de la base local.');
      widget.onCambio();
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
// Fila de un cliente pendiente (todavía no se intentó subir)
// =============================================================================

class _FilaPendiente extends StatelessWidget {
  final Cliente cliente;
  final VoidCallback onCambio;

  const _FilaPendiente({required this.cliente, required this.onCambio});

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
    final confirmar = await _confirmarEliminar(context, cliente);
    if (!confirmar || !context.mounted) return;
    try {
      await context
          .read<ClientesProvider>()
          .eliminarClienteLocal(cliente.idLocal);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente eliminado de la base local.')),
      );
      onCambio();
    } on StateError catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

// =============================================================================
// Helpers compartidos
// =============================================================================

/// Convierte el JSON de coincidencias (tal y como lo guardó
/// [SyncClientesService] al recibir un 409) en una lista de [Cliente] que
/// pueda mostrarse en el [DialogoCoincidenciasCif].
///
/// Como estos clientes vienen del servidor pero son solo para visualización,
/// se les asigna un `idLocal` ficticio basado en el id del servidor — nunca
/// se persisten en SQLite.
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

/// Diálogo de confirmación común antes de borrar un cliente local.
Future<bool> _confirmarEliminar(BuildContext context, Cliente cliente) async {
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
          style: FilledButton.styleFrom(
              foregroundColor: Colors.red.shade700),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
