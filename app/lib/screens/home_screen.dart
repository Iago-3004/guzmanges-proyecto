import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

/// Pantalla principal provisional tras iniciar sesión.
/// En los próximos pasos se sustituirá por el listado de clientes.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('GuzmanGes'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            Text('Sesión iniciada como ${auth.nombreUsuario ?? ''}'),
            const SizedBox(height: 4),
            Text('Rol: ${auth.rol ?? ''}'),
          ],
        ),
      ),
    );
  }
}
