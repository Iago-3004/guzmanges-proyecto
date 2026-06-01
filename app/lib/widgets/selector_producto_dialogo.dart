import 'package:flutter/material.dart';

import '../models/producto.dart';

/// Diálogo de tela completa para escoger un producto al añadir una línea
/// al pedido. Filtra por descripción, referencia o código de barras, todo
/// en memoria a partir de la lista cargada (los productos son catálogo
/// local, no hace falta volver al servidor).
class SelectorProductoDialogo extends StatefulWidget {
  final List<Producto> productos;

  const SelectorProductoDialogo({super.key, required this.productos});

  static Future<Producto?> mostrar(
    BuildContext context, {
    required List<Producto> productos,
  }) {
    return Navigator.of(context).push<Producto>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SelectorProductoDialogo(productos: productos),
      ),
    );
  }

  @override
  State<SelectorProductoDialogo> createState() =>
      _SelectorProductoDialogoState();
}

class _SelectorProductoDialogoState extends State<SelectorProductoDialogo> {
  final TextEditingController _buscador = TextEditingController();
  String _filtro = '';

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  List<Producto> get _filtrados {
    final texto = _filtro.trim().toLowerCase();
    if (texto.isEmpty) return widget.productos;
    bool casa(String? v) => v != null && v.toLowerCase().contains(texto);
    return widget.productos
        .where((p) =>
            casa(p.descripcion) ||
            casa(p.referencia) ||
            casa(p.codigoBarras))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final productos = _filtrados;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleccionar producto'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _buscador,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Buscar por descripción, referencia o código',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _filtro.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _buscador.clear();
                          setState(() => _filtro = '');
                        },
                      ),
                isDense: true,
              ),
              onChanged: (texto) => setState(() => _filtro = texto),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${productos.length} '
                '${productos.length == 1 ? "producto" : "productos"}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: productos.isEmpty
                ? const _Vacio()
                : ListView.builder(
                    itemCount: productos.length,
                    itemBuilder: (context, index) {
                      final p = productos[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(_inicial(p.descripcion)),
                        ),
                        title: Text(
                          p.descripcion,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: _subtitulo(p),
                        trailing: p.precioVenta != null
                            ? Text(
                                _formatearPrecio(p.precioVenta!),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                        onTap: () => Navigator.of(context).pop(p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget? _subtitulo(Producto p) {
    final partes = <String>[];
    if (p.referencia != null && p.referencia!.isNotEmpty) {
      partes.add(p.referencia!);
    }
    final stock = p.stock ?? 0;
    partes.add(stock > 0 ? 'Stock: $stock' : 'Sin stock');
    return Text(partes.join(' · '));
  }

  String _inicial(String texto) {
    final limpio = texto.trim();
    if (limpio.isEmpty) return '?';
    return limpio.substring(0, 1).toUpperCase();
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

class _Vacio extends StatelessWidget {
  const _Vacio();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No hay productos que coincidan.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
