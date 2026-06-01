import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/pedidos_provider.dart';
import '../../widgets/pedido_tile.dart';
import 'pedido_detalle_screen.dart';
import 'pedido_form_screen.dart';

/// Pantalla principal de pedidos. Lista los pedidos guardados en local,
/// permite buscar por número o cliente, filtrar a "solo pendientes" y
/// abrir el alta de uno nuevo desde el FAB.
class PedidosListaScreen extends StatefulWidget {
  const PedidosListaScreen({super.key});

  @override
  State<PedidosListaScreen> createState() => _PedidosListaScreenState();
}

class _PedidosListaScreenState extends State<PedidosListaScreen> {
  final TextEditingController _buscador = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PedidosProvider>().recargarDesdeLocal();
    });
  }

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PedidosProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos'),
      ),
      body: Column(
        children: [
          _buscadorYContador(context, provider),
          _filtroSoloPendientes(context, provider),
          Expanded(child: _construirCuerpo(context, provider)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _irANuevoPedido(context),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo pedido'),
      ),
    );
  }

  Widget _buscadorYContador(BuildContext context, PedidosProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _buscador,
            decoration: InputDecoration(
              hintText: 'Buscar por número o cliente',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _buscador.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _buscador.clear();
                        context.read<PedidosProvider>().aplicarFiltro('');
                      },
                    ),
              isDense: true,
            ),
            onChanged: (texto) {
              context.read<PedidosProvider>().aplicarFiltro(texto);
            },
          ),
          if (!provider.cargando && provider.pedidos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                '${provider.pedidos.length} '
                '${provider.pedidos.length == 1 ? "pedido" : "pedidos"}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filtroSoloPendientes(BuildContext context, PedidosProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
      child: SwitchListTile(
        value: provider.soloPendientes,
        onChanged: (v) =>
            context.read<PedidosProvider>().aplicarSoloPendientes(v),
        title: const Text('Solo pendientes de sincronizar'),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  Widget _construirCuerpo(BuildContext context, PedidosProvider provider) {
    if (provider.cargando && provider.pedidos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.pedidos.isEmpty) {
      return _MensajeVacio(
        hayFiltro: provider.filtro.isNotEmpty || provider.soloPendientes,
      );
    }
    return RefreshIndicator(
      onRefresh: () => context.read<PedidosProvider>().recargarDesdeLocal(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 96),
        itemCount: provider.pedidos.length,
        itemBuilder: (context, index) {
          final pedido = provider.pedidos[index];
          return PedidoTile(
            pedido: pedido,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      PedidoDetalleScreen(idLocal: pedido.idLocal),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _irANuevoPedido(BuildContext context) async {
    // Capturamos la referencia al provider ANTES del await: tras volver del
    // form la State podría haberse desmontado (lint context_across_async).
    final provider = context.read<PedidosProvider>();
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PedidoFormScreen()),
    );
    if (guardado == true && mounted) {
      provider.recargarDesdeLocal();
    }
  }
}

class _MensajeVacio extends StatelessWidget {
  final bool hayFiltro;

  const _MensajeVacio({required this.hayFiltro});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hayFiltro ? Icons.search_off : Icons.receipt_long_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              hayFiltro
                  ? 'Ningún pedido coincide con la búsqueda.'
                  : 'No hay pedidos guardados.\nPulsa "Nuevo pedido" para crear el primero.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
