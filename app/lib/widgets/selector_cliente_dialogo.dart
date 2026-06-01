import 'package:flutter/material.dart';

import '../models/cliente.dart';

/// Diálogo de tela completa para escoger un cliente al construir un pedido.
///
/// Recibe la lista ya cargada de SQLite (no acopla a un provider concreto)
/// y filtra en memoria por nombre comercial, razón social y CIF. Incluye
/// también los clientes PENDENTE: el preventa debe poder capturar un pedido
/// para un cliente recién dado de alta aunque todavía no esté sincronizado.
///
/// Para abrirlo, usa el helper estático [SelectorClienteDialogo.mostrar].
/// Devuelve el [Cliente] elegido o null si se canceló.
class SelectorClienteDialogo extends StatefulWidget {
  final List<Cliente> clientes;

  const SelectorClienteDialogo({super.key, required this.clientes});

  static Future<Cliente?> mostrar(
    BuildContext context, {
    required List<Cliente> clientes,
  }) {
    return Navigator.of(context).push<Cliente>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SelectorClienteDialogo(clientes: clientes),
      ),
    );
  }

  @override
  State<SelectorClienteDialogo> createState() =>
      _SelectorClienteDialogoState();
}

class _SelectorClienteDialogoState extends State<SelectorClienteDialogo> {
  final TextEditingController _buscador = TextEditingController();
  String _filtro = '';

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  List<Cliente> get _filtrados {
    final texto = _filtro.trim().toLowerCase();
    if (texto.isEmpty) return widget.clientes;
    bool casa(String? v) => v != null && v.toLowerCase().contains(texto);
    return widget.clientes
        .where((c) => casa(c.nombreComercial) || casa(c.razonSocial) || casa(c.cif))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final clientes = _filtrados;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleccionar cliente'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _buscador,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, razón social o CIF',
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
                '${clientes.length} '
                '${clientes.length == 1 ? "cliente" : "clientes"}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: clientes.isEmpty
                ? const _Vacio()
                : ListView.builder(
                    itemCount: clientes.length,
                    itemBuilder: (context, index) {
                      final c = clientes[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(_inicial(c.nombreComercial)),
                        ),
                        title: Text(c.nombreComercial),
                        subtitle: _subtitulo(c),
                        trailing: c.estadoSync == EstadoSync.sincronizado
                            ? null
                            : Tooltip(
                                message: 'Cliente todavía sin sincronizar',
                                child: Icon(
                                  Icons.cloud_upload,
                                  color: Colors.amber.shade700,
                                ),
                              ),
                        onTap: () => Navigator.of(context).pop(c),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget? _subtitulo(Cliente c) {
    final partes = <String>[];
    if (c.cif != null && c.cif!.isNotEmpty) partes.add(c.cif!);
    if (c.localidad != null && c.localidad!.isNotEmpty) partes.add(c.localidad!);
    if (partes.isEmpty) return null;
    return Text(partes.join(' · '));
  }

  String _inicial(String nombre) {
    final limpio = nombre.trim();
    if (limpio.isEmpty) return '?';
    return limpio.substring(0, 1).toUpperCase();
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
              'No hay clientes que coincidan.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
