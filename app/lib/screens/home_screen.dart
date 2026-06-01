import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/clientes_provider.dart';
import '../providers/pedidos_provider.dart';
import '../providers/sync_provider.dart';
import '../widgets/dialogo_resumen_sync.dart';
import '../widgets/dialogo_sincronizar.dart';
import 'acerca_de_screen.dart';
import 'clientes/clientes_lista_screen.dart';
import 'pedidos/pedidos_lista_screen.dart';
import 'productos/productos_lista_screen.dart';
import 'sync/estado_sync_screen.dart';

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
              leading: const Icon(Icons.inventory_2),
              title: const Text('Productos'),
              onTap: () {
                Navigator.of(context).pop();
                _irAProductos(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Pedidos'),
              onTap: () {
                Navigator.of(context).pop();
                _irAPedidos(context);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.sync_problem),
              title: const Text('Estado de sincronización'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const EstadoSyncScreen(),
                  ),
                );
              },
            ),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Acerca de'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AcercaDeScreen(),
                  ),
                );
              },
            ),
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
        const SizedBox(height: 16),
        const _BannerEstadoSync(),
        const SizedBox(height: 8),
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
          descripcion: 'Consulta del catálogo y stock disponible.',
          onTap: () => _irAProductos(context),
        ),
        const SizedBox(height: 12),
        _TarjetaSeccion(
          icono: Icons.receipt_long,
          titulo: 'Pedidos',
          descripcion: 'Alta y consulta de pedidos de venta.',
          onTap: () => _irAPedidos(context),
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

  void _irAProductos(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProductosListaScreen()),
    );
  }

  void _irAPedidos(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PedidosListaScreen()),
    );
  }

  Future<void> _sincronizar() async {
    final sync = context.read<SyncProvider>();
    try {
      final resultado = await sync.sincronizarTodo();
      if (!mounted) return;

      // Sesión caducada tiene su propio diálogo (acción a tomar:
      // reautenticarse). El resto va al diálogo de resumen, que cubre tanto
      // el "todo bien" como el "con errores" con el mismo formato y un
      // botón directo para resolver si hay errores.
      if (resultado.sesionCaducada) {
        await _mostrarDialogoSesionCaducada();
      } else {
        await DialogoResumenSync.mostrar(
          context,
          resultado: resultado,
          onVerEstado: resultado.hayErrores
              ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const EstadoSyncScreen()),
                  )
              : null,
        );
      }
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

  /// Diálogo central cuando el servidor ha respondido 401 a mitad de la
  /// sincronización. El AuthProvider ya hace el logout por su lado al
  /// detectar el 401; aquí solo damos contexto visual.
  Future<void> _mostrarDialogoSesionCaducada() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.lock_clock,
            color: Theme.of(ctx).colorScheme.error, size: 40),
        title: const Text('Sesión caducada'),
        content: const Text(
          'La sesión ha caducado durante la sincronización. '
          'Vuelve a iniciar sesión para continuar.',
          textAlign: TextAlign.center,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  String _iniciales(String? nombre) {
    if (nombre == null || nombre.isEmpty) return '?';
    return nombre.substring(0, 1).toUpperCase();
  }
}

/// Banner persistente que avisa de clientes o pedidos pendientes o con
/// error de sincronización. Se oculta cuando todo está al día. Al tocarlo
/// lleva a la pantalla [EstadoSyncScreen] para que el usuario revise y
/// resuelva.
///
/// Suma los contadores de clientes y pedidos para que el aviso refleje el
/// estado global de la app: el usuario no debería tener que mirar dos
/// pantallas distintas para saber si hay trabajo pendiente.
///
/// El color y el texto cambian según haya solo pendientes (ámbar) o
/// también errores (rojo), para que el usuario distinga de un vistazo si
/// debe actuar o simplemente esperar a la próxima sincronización.
class _BannerEstadoSync extends StatelessWidget {
  const _BannerEstadoSync();

  @override
  Widget build(BuildContext context) {
    final clientes = context.watch<ClientesProvider>();
    final pedidos = context.watch<PedidosProvider>();

    final clientesPend = clientes.pendientes;
    final clientesErr = clientes.conError;
    final pedidosPend = pedidos.pendientes;
    final pedidosErr = pedidos.conError;

    final pendientes = clientesPend + pedidosPend;
    final conError = clientesErr + pedidosErr;
    if (pendientes == 0 && conError == 0) return const SizedBox.shrink();

    final hayError = conError > 0;
    // Paleta de tonos claramente separados para que el texto contraste bien
    // sobre el fondo, evitando el efecto "ámbar sobre ámbar" en el que el
    // mensaje se mezclaba con el card.
    final fondo = hayError ? Colors.red.shade50 : Colors.amber.shade50;
    final borde = hayError ? Colors.red.shade300 : Colors.amber.shade400;
    final colorIcono = hayError ? Colors.red.shade700 : Colors.amber.shade800;
    final colorTexto = hayError ? Colors.red.shade900 : Colors.amber.shade900;
    final colorSubtexto =
        hayError ? Colors.red.shade800 : Colors.amber.shade800;

    final icono = hayError ? Icons.error_outline : Icons.cloud_upload;
    final accion = hayError ? 'Toca para resolver' : 'Toca para revisar';
    final mensaje = _construirMensaje(
      clientesPend: clientesPend,
      clientesErr: clientesErr,
      pedidosPend: pedidosPend,
      pedidosErr: pedidosErr,
    );

    return Card(
      margin: EdgeInsets.zero,
      color: fondo,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borde),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EstadoSyncScreen()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icono, color: colorIcono, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mensaje,
                      style: TextStyle(
                        color: colorTexto,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      accion,
                      style: TextStyle(
                        color: colorSubtexto,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorIcono),
            ],
          ),
        ),
      ),
    );
  }

  /// Construye el texto del banner desglosando por tipo de entidad. Cuando
  /// hay errores se mencionan antes que los pendientes para que el usuario
  /// los priorice. Se enumeran clientes y pedidos por separado para que
  /// quede claro qué tocar (la pantalla de estado tiene secciones distintas).
  String _construirMensaje({
    required int clientesPend,
    required int clientesErr,
    required int pedidosPend,
    required int pedidosErr,
  }) {
    final partesErr = <String>[];
    if (clientesErr > 0) {
      partesErr.add('$clientesErr '
          'cliente${clientesErr == 1 ? '' : 's'} con error');
    }
    if (pedidosErr > 0) {
      partesErr.add('$pedidosErr '
          'pedido${pedidosErr == 1 ? '' : 's'} con error');
    }
    final partesPend = <String>[];
    if (clientesPend > 0) {
      partesPend.add('$clientesPend '
          'cliente${clientesPend == 1 ? '' : 's'} pendiente${clientesPend == 1 ? '' : 's'}');
    }
    if (pedidosPend > 0) {
      partesPend.add('$pedidosPend '
          'pedido${pedidosPend == 1 ? '' : 's'} pendiente${pedidosPend == 1 ? '' : 's'}');
    }

    if (partesErr.isNotEmpty) {
      final base = 'Hay ${partesErr.join(' y ')}';
      if (partesPend.isEmpty) return '$base de sincronización.';
      return '$base y ${partesPend.join(' y ')} de enviar.';
    }
    return 'Hay ${partesPend.join(' y ')} de enviar al servidor.';
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
