import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/sync_provider.dart';
import '../widgets/dialogo_sincronizar.dart';
import 'clientes/clientes_lista_screen.dart';

/// Pantalla principal tras iniciar sesión.
///
/// Muestra:
/// - Cards grandes para acceder a las secciones (Clientes, Productos,
///   Pedidos). Productos y Pedidos están deshabilitados a la espera de
///   que se implementen.
/// - Drawer lateral con accesos rápidos.
/// - FAB extendido "Sincronizar" que descarga catálogos y clientes desde
///   el servidor.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Si el usuario acaba de iniciar sesión, le ofrecemos sincronizar.
    // No se hace al abrir la app con sesión persistida: el flag del
    // AuthProvider solo se activa tras un login con éxito.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ofrecerSincronizacionTrasLogin();
    });
  }

  Future<void> _ofrecerSincronizacionTrasLogin() async {
    if (!mounted) return;
    final acaba = context.read<AuthProvider>().consumirSolicitudSincronizacion();
    if (!acaba) return;
    final aceptar = await DialogoSincronizar.mostrar(context);
    if (!aceptar || !mounted) return;
    await _sincronizar();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final sync = context.watch<SyncProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('GuzmanGes'),
      ),
      drawer: _construirDrawer(context, auth),
      body: _construirCuerpo(context, auth),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: sync.sincronizando ? null : _sincronizar,
        icon: sync.sincronizando
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.sync),
        label: Text(sync.sincronizando ? 'Sincronizando…' : 'Sincronizar'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  // ---------------------------------------------------------------------------
  // Drawer
  // ---------------------------------------------------------------------------

  Widget _construirDrawer(BuildContext context, AuthProvider auth) {
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(color: scheme.primary),
              accountName: Text(auth.nombreUsuario ?? ''),
              accountEmail: Text('Rol: ${auth.rol ?? ''}'),
              currentAccountPicture: CircleAvatar(
                backgroundColor: scheme.onPrimary,
                foregroundColor: scheme.primary,
                child: Text(
                  _iniciales(auth.nombreUsuario),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Clientes'),
              onTap: () {
                Navigator.of(context).pop();
                _irAClientes(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.sync_problem),
              title: const Text('Estado de sincronización'),
              subtitle: const Text('Próximamente'),
              enabled: false,
            ),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Cerrar sesión'),
              onTap: () {
                Navigator.of(context).pop();
                context.read<AuthProvider>().logout();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cuerpo con las cards
  // ---------------------------------------------------------------------------

  Widget _construirCuerpo(BuildContext context, AuthProvider auth) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text(
          'Hola, ${auth.nombreUsuario ?? ''}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
        _TarjetaSeccion(
          icono: Icons.people,
          titulo: 'Clientes',
          descripcion: 'Consulta y alta de la cartera de clientes.',
          onTap: () => _irAClientes(context),
        ),
        const SizedBox(height: 12),
        _TarjetaSeccion(
          icono: Icons.inventory_2,
          titulo: 'Productos',
          descripcion: 'Próximamente.',
          onTap: null,
        ),
        const SizedBox(height: 12),
        _TarjetaSeccion(
          icono: Icons.receipt_long,
          titulo: 'Pedidos',
          descripcion: 'Próximamente.',
          onTap: null,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Acciones
  // ---------------------------------------------------------------------------

  void _irAClientes(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ClientesListaScreen()),
    );
  }

  Future<void> _sincronizar() async {
    final sync = context.read<SyncProvider>();
    try {
      final resultado = await sync.sincronizarTodo();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: resultado.sesionCaducada
              ? Theme.of(context).colorScheme.error
              : Colors.green.shade700,
          content: Text(resultado.resumen()),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text(
              'Error al sincronizar: ${e.toString().replaceFirst('Exception: ', '')}'),
        ),
      );
    }
  }

  String _iniciales(String? nombre) {
    if (nombre == null || nombre.isEmpty) return '?';
    return nombre.substring(0, 1).toUpperCase();
  }
}

/// Card grande con icono, título y descripción para acceder a una sección.
/// Si [onTap] es null, se muestra deshabilitada (placeholder).
class _TarjetaSeccion extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String descripcion;
  final VoidCallback? onTap;

  const _TarjetaSeccion({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final habilitada = onTap != null;
    final colorIcono = habilitada ? scheme.primary : Colors.grey;
    return Card(
      elevation: habilitada ? 2 : 0,
      color: habilitada ? null : Colors.grey.shade100,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: colorIcono.withValues(alpha: 0.15),
                child: Icon(icono, color: colorIcono, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: habilitada ? null : Colors.grey,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      descripcion,
                      style: TextStyle(
                        color: habilitada ? Colors.grey.shade700 : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              if (habilitada)
                const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
