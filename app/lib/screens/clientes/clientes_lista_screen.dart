import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/catalogos_provider.dart';
import '../../providers/clientes_provider.dart';
import '../../widgets/cliente_tile.dart';
import 'cliente_detalle_screen.dart';
import 'cliente_form_screen.dart';

/// Pantalla con la lista de clientes en caché local.
///
/// Lee siempre de SQLite (vía [ClientesProvider]); la sincronización con el
/// servidor se dispara desde otros puntos de la app, no desde aquí. Permite
/// búsqueda por texto, filtros por modo y condición de pago, y dar de alta
/// un cliente nuevo con el botón flotante.
class ClientesListaScreen extends StatefulWidget {
  const ClientesListaScreen({super.key});

  @override
  State<ClientesListaScreen> createState() => _ClientesListaScreenState();
}

class _ClientesListaScreenState extends State<ClientesListaScreen> {
  final TextEditingController _buscador = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Refresca al entrar por si la BD cambió desde otra pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ClientesProvider>().recargarDesdeLocal();
    });
  }

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ClientesProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
      ),
      body: Column(
        children: [
          _buscadorYContador(context, provider),
          const _PanelFiltros(),
          Expanded(child: _construirCuerpo(context, provider)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ClienteFormScreen()),
          );
          // Al volver, refresca por si se ha dado de alta un cliente.
          if (context.mounted) {
            context.read<ClientesProvider>().recargarDesdeLocal();
          }
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nuevo cliente'),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cabecera: buscador y contador de resultados
  // ---------------------------------------------------------------------------

  Widget _buscadorYContador(BuildContext context, ClientesProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _buscador,
            decoration: InputDecoration(
              hintText: 'Buscar por nombre, razón social o CIF',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _buscador.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _buscador.clear();
                        context.read<ClientesProvider>().aplicarFiltro('');
                      },
                    ),
              isDense: true,
            ),
            onChanged: (texto) {
              context.read<ClientesProvider>().aplicarFiltro(texto);
            },
          ),
          if (!provider.cargando && provider.clientes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                '${provider.clientes.length} '
                '${provider.clientes.length == 1 ? "cliente" : "clientes"}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cuerpo principal (lista, mensaje vacío o spinner)
  // ---------------------------------------------------------------------------

  Widget _construirCuerpo(BuildContext context, ClientesProvider provider) {
    if (provider.cargando && provider.clientes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.clientes.isEmpty) {
      return _MensajeVacio(
        filtroTexto: provider.filtro,
        hayFiltrosExtra: provider.numeroFiltrosActivos > 0,
      );
    }
    return RefreshIndicator(
      onRefresh: () => context.read<ClientesProvider>().recargarDesdeLocal(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        itemCount: provider.clientes.length,
        itemBuilder: (context, index) {
          final cliente = provider.clientes[index];
          return ClienteTile(
            cliente: cliente,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ClienteDetalleScreen(idLocal: cliente.idLocal),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// =============================================================================
// Panel de filtros desplegable (modo de pago y condición de pago)
// =============================================================================

class _PanelFiltros extends StatelessWidget {
  const _PanelFiltros();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clientes = context.watch<ClientesProvider>();
    final catalogos = context.watch<CatalogosProvider>();
    final activos = clientes.numeroFiltrosActivos;

    return Theme(
      // ExpansionTile aplica un divider en M3; lo quitamos para integrarlo
      // mejor con el resto de la cabecera.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(Icons.filter_list, color: scheme.primary),
        title: Row(
          children: [
            const Text('Filtros'),
            if (activos > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$activos',
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        trailing: activos > 0
            ? TextButton.icon(
                onPressed: () => context
                    .read<ClientesProvider>()
                    .limpiarFiltrosDespegable(),
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('Limpiar'),
              )
            : null,
        childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          DropdownButtonFormField<int?>(
            initialValue: clientes.filtroModoPagoId,
            isExpanded: true,
            decoration: _decoracionFiltro('Modo de pago'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Todos')),
              for (final m in catalogos.modos)
                DropdownMenuItem<int?>(
                  value: m.id,
                  child: Text(m.descripcion),
                ),
            ],
            onChanged: (valor) {
              context.read<ClientesProvider>().aplicarFiltroModoPago(valor);
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int?>(
            initialValue: clientes.filtroCondicionPagoId,
            isExpanded: true,
            decoration: _decoracionFiltro('Condición de pago'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Todas')),
              for (final c in catalogos.condiciones)
                DropdownMenuItem<int?>(
                  value: c.id,
                  child: Text(c.descripcion),
                ),
            ],
            onChanged: (valor) {
              context
                  .read<ClientesProvider>()
                  .aplicarFiltroCondicionPago(valor);
            },
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            value: clientes.filtroSoloPendientes,
            onChanged: (valor) {
              context
                  .read<ClientesProvider>()
                  .aplicarFiltroSoloPendientes(valor);
            },
            contentPadding: EdgeInsets.zero,
            title: const Text('Solo pendientes de sincronizar'),
            subtitle: const Text(
              'Clientes creados que aún no se han enviado al servidor',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// Decoración común de los dos dropdowns. Usa siempre el label flotante
  /// (FloatingLabelBehavior.always) y un OutlineInputBorder con [gapPadding]
  /// generoso para que el texto del label no se vea cortado por el borde.
  InputDecoration _decoracionFiltro(String etiqueta) {
    return InputDecoration(
      labelText: etiqueta,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      border: const OutlineInputBorder(gapPadding: 8),
      enabledBorder: const OutlineInputBorder(gapPadding: 8),
      focusedBorder: const OutlineInputBorder(gapPadding: 8),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}

// =============================================================================
// Mensaje cuando no hay resultados (vacío total o por filtros muy restrictivos)
// =============================================================================

class _MensajeVacio extends StatelessWidget {
  final String filtroTexto;
  final bool hayFiltrosExtra;

  const _MensajeVacio({
    required this.filtroTexto,
    required this.hayFiltrosExtra,
  });

  @override
  Widget build(BuildContext context) {
    final hayBusqueda = filtroTexto.isNotEmpty || hayFiltrosExtra;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hayBusqueda ? Icons.search_off : Icons.cloud_off,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              hayBusqueda
                  ? 'Ningún cliente coincide con la búsqueda o los filtros.'
                  : 'No hay clientes en local.\nPulsa "Sincronizar" en la pantalla principal para descargarlos.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
