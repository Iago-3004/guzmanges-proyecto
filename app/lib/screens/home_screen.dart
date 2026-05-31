import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/clientes_provider.dart';
import '../providers/sync_provider.dart';
import '../widgets/dialogo_sincronizar.dart';
import 'clientes/clientes_lista_screen.dart';
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

  void _irAProductos(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProductosListaScreen()),
    );
  }

  Future<void> _sincronizar() async {
    final sync = context.read<SyncProvider>();
    try {
      final resultado = await sync.sincronizarTodo();
      if (!mounted) return;

      // Cuando hay errores o la sesión caduca, un SnackBar pasa fácilmente
      // desapercibido. Se sustituye por un diálogo central que obligue al
      // usuario a reaccionar (o al menos a leer el aviso).
      if (resultado.sesionCaducada) {
        await _mostrarDialogoSesionCaducada();
      } else if (resultado.clientesConError > 0) {
        await _mostrarDialogoConErrores(resultado);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text(resultado.resumen()),
          ),
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

  /// Diálogo central tras una sincronización en la que algún cliente no se
  /// pudo enviar. Ofrece ir directamente a la pantalla de estado para
  /// resolverlos o cerrarlo y revisarlos más tarde.
  Future<void> _mostrarDialogoConErrores(ResultadoSincronizacion r) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded,
            color: Colors.amber.shade700, size: 40),
        title: const Text('Sincronización con avisos'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Se han descargado ${r.clientesBajados} '
              'cliente${r.clientesBajados == 1 ? '' : 's'} y enviado '
              '${r.clientesSubidos}.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              '${r.clientesConError} '
              'cliente${r.clientesConError == 1 ? ' ha quedado' : 's han quedado'} '
              'con error y necesita${r.clientesConError == 1 ? '' : 'n'} tu revisión.',
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
          FilledButton.tonal(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EstadoSyncScreen()),
              );
            },
            child: const Text('Ver estado'),
          ),
        ],
      ),
    );
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

/// Banner persistente que avisa de clientes pendientes o con error de
/// sincronización. Se oculta cuando todo está al día. Al tocarlo lleva a la
/// pantalla [EstadoSyncScreen] para que el usuario revise y resuelva.
///
/// El color y el texto cambian según haya solo pendientes (ámbar) o
/// también errores (rojo), para que el usuario distinga de un vistazo si
/// debe actuar o simplemente esperar a la próxima sincronización.
class _BannerEstadoSync extends StatelessWidget {
  const _BannerEstadoSync();

  @override
  Widget build(BuildContext context) {
    final clientes = context.watch<ClientesProvider>();
    final pendientes = clientes.pendientes;
    final conError = clientes.conError;
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
    final mensaje = _construirMensaje(pendientes, conError);

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

  /// Construye el texto del banner según cuántos pendientes y errores haya.
  /// Cuando hay errores, esos predominan en la frase para que el usuario
  /// los priorice; los pendientes se mencionan como complemento si los hay.
  String _construirMensaje(int pendientes, int conError) {
    if (conError > 0) {
      final base =
          'Hay $conError cliente${conError == 1 ? '' : 's'} con error de sincronización';
      if (pendientes > 0) {
        return '$base y $pendientes pendiente${pendientes == 1 ? '' : 's'} de enviar.';
      }
      return '$base.';
    }
    return 'Hay $pendientes cliente${pendientes == 1 ? '' : 's'} '
        'pendiente${pendientes == 1 ? '' : 's'} de enviar al servidor.';
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
