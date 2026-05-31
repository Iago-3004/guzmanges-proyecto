import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/cliente.dart';
import '../../providers/clientes_provider.dart';
import '../../widgets/chip_estado_sync.dart';

/// Vista de solo lectura con el detalle de un cliente.
///
/// Recibe el `id_local` (UUID) y resuelve la entidad contra SQLite. Se hace
/// así (en vez de pasar el [Cliente] entero) para que si el cliente cambia
/// en la BD mientras la pantalla está abierta, al rehacer un `setState` se
/// reflejen los cambios.
class ClienteDetalleScreen extends StatefulWidget {
  final String idLocal;

  const ClienteDetalleScreen({super.key, required this.idLocal});

  @override
  State<ClienteDetalleScreen> createState() => _ClienteDetalleScreenState();
}

class _ClienteDetalleScreenState extends State<ClienteDetalleScreen> {
  late Future<Cliente?> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = context.read<ClientesProvider>().obtener(widget.idLocal);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Cliente?>(
      future: _futuro,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: const Text('Cliente')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final cliente = snapshot.data;
        if (cliente == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Cliente')),
            body: const Center(child: Text('Cliente no encontrado')),
          );
        }
        // Solo se puede borrar localmente lo que aún no se subió al servidor:
        // los sincronizados se volverían a descargar en la próxima sync.
        final puedeEliminar = cliente.idServidor == null;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Cliente'),
            actions: [
              if (puedeEliminar)
                IconButton(
                  tooltip: 'Eliminar localmente',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmarEliminacion(context, cliente),
                ),
            ],
          ),
          body: _construirContenido(context, cliente),
        );
      },
    );
  }

  /// Pide confirmación al usuario y, si acepta, elimina el cliente de SQLite
  /// y vuelve a la lista.
  Future<void> _confirmarEliminacion(
      BuildContext context, Cliente cliente) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded,
            color: Colors.amber.shade700, size: 36),
        title: const Text('Eliminar cliente'),
        content: Text(
          '¿Seguro que quiere eliminar "${cliente.nombreComercial}"? '
          'Esta acción no se puede deshacer.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    if (!context.mounted) return;
    try {
      await context.read<ClientesProvider>().eliminarClienteLocal(cliente.idLocal);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: const Text('Cliente eliminado.'),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text('No se pudo eliminar: ${e.toString().replaceFirst('Exception: ', '')}'),
        ),
      );
    }
  }

  Widget _construirContenido(BuildContext context, Cliente cliente) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _Cabecera(cliente: cliente),
        if (cliente.mensajeError != null) ...[
          const SizedBox(height: 16),
          _BloqueError(mensaje: cliente.mensajeError!),
        ],
        const SizedBox(height: 16),
        _SeccionCard(
          icono: Icons.badge_outlined,
          titulo: 'Identificación',
          filas: [
            _FilaCampo(icono: Icons.numbers, etiqueta: 'CIF', valor: cliente.cif),
            _FilaCampo(
              icono: Icons.business,
              etiqueta: 'Razón social',
              valor: cliente.razonSocial,
            ),
          ],
        ),
        _SeccionCard(
          icono: Icons.location_on_outlined,
          titulo: 'Dirección',
          filas: [
            _FilaCampo(
              icono: Icons.home_outlined,
              etiqueta: 'Dirección',
              valor: cliente.direccion,
            ),
            _FilaCampo(
              icono: Icons.location_city,
              etiqueta: 'Localidad',
              valor: cliente.localidad,
            ),
            _FilaCampo(
              icono: Icons.markunread_mailbox_outlined,
              etiqueta: 'Código postal',
              valor: cliente.codigoPostal,
            ),
            _FilaCampo(
              icono: Icons.map_outlined,
              etiqueta: 'Provincia',
              valor: cliente.provincia,
            ),
          ],
        ),
        _SeccionCard(
          icono: Icons.contact_phone_outlined,
          titulo: 'Contacto',
          filas: [
            _FilaCampo(
              icono: Icons.phone_outlined,
              etiqueta: 'Teléfono',
              valor: cliente.telefono,
            ),
            _FilaCampo(
              icono: Icons.smartphone,
              etiqueta: 'Móvil',
              valor: cliente.movil,
            ),
            _FilaCampo(
              icono: Icons.email_outlined,
              etiqueta: 'Email',
              valor: cliente.email,
            ),
          ],
        ),
        _SeccionCard(
          icono: Icons.payments_outlined,
          titulo: 'Condiciones de pago',
          filas: [
            _FilaCampo(
              icono: Icons.payment,
              etiqueta: 'Modo de pago',
              valor: cliente.modoPagoDescripcion,
            ),
            _FilaCampo(
              icono: Icons.schedule,
              etiqueta: 'Condición de pago',
              valor: cliente.condicionPagoDescripcion,
            ),
            _FilaCampo(
              icono: Icons.account_balance,
              etiqueta: 'Posición fiscal',
              valor: cliente.posicionFiscal,
            ),
          ],
        ),
        _SeccionCard(
          icono: Icons.person_pin_outlined,
          titulo: 'Comercial asignado',
          filas: [
            _FilaCampo(
              icono: Icons.person_outline,
              etiqueta: 'Comercial',
              valor: cliente.comercial,
            ),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// Cabecera con el nombre, razón social, CIF y chip de estado
// =============================================================================

class _Cabecera extends StatelessWidget {
  final Cliente cliente;

  const _Cabecera({required this.cliente});

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            child: Text(
              _inicial(cliente.nombreComercial),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cliente.nombreComercial,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onPrimaryContainer,
                      ),
                ),
                if (cliente.cif != null && cliente.cif!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    cliente.cif!,
                    style: TextStyle(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChipEstadoSync(
                      estado: cliente.estadoSync,
                      ocultarSiSincronizado: false,
                    ),
                    _ChipActivo(activo: cliente.activo),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _inicial(String nombre) {
    final limpio = nombre.trim();
    if (limpio.isEmpty) return '?';
    return limpio.substring(0, 1).toUpperCase();
  }
}

// =============================================================================
// Card de sección con icono, título y filas
// =============================================================================

class _SeccionCard extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final List<_FilaCampo> filas;

  const _SeccionCard({
    required this.icono,
    required this.titulo,
    required this.filas,
  });

  @override
  Widget build(BuildContext context) {
    // Solo muestra filas con valor; si la sección queda vacía, se oculta entera.
    final visibles = filas.where((f) => f.tieneValor).toList();
    if (visibles.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icono, color: scheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    titulo,
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ...visibles,
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Fila campo (icono + etiqueta + valor); se oculta si valor está vacío
// =============================================================================

class _FilaCampo extends StatelessWidget {
  final IconData icono;
  final String etiqueta;
  final String? valor;

  const _FilaCampo({
    required this.icono,
    required this.etiqueta,
    required this.valor,
  });

  bool get tieneValor => valor != null && valor!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!tieneValor) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor!,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Chip que indica si el cliente está activo o inactivo
// =============================================================================

class _ChipActivo extends StatelessWidget {
  final bool activo;

  const _ChipActivo({required this.activo});

  @override
  Widget build(BuildContext context) {
    final color = activo ? Colors.green : Colors.grey;
    final texto = activo ? 'Activo' : 'Inactivo';
    final icono = activo ? Icons.check_circle : Icons.cancel;
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

// =============================================================================
// Bloque destacado de error de sincronización
// =============================================================================

class _BloqueError extends StatelessWidget {
  final String mensaje;

  const _BloqueError({required this.mensaje});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
