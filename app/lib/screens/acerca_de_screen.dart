import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/db/database_helper.dart';
import '../core/storage/token_storage.dart';
import '../providers/app_config_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/catalogos_provider.dart';
import '../providers/clientes_provider.dart';
import '../providers/pedidos_provider.dart';
import '../providers/productos_provider.dart';

/// Pantalla "Acerca de": muestra la información básica de la aplicación
/// (logo, nombre y versión) y un botón destructivo para borrar todos los
/// datos locales y volver al estado de "recién instalada".
///
/// Pensada como punto de salida cuando el usuario quiere cambiar de servidor
/// (otra URL de API) o resetear la app por completo: no hay otra forma desde
/// la UI de volver a la pantalla de configuración del servidor sin
/// desinstalar.
class AcercaDeScreen extends StatefulWidget {
  const AcercaDeScreen({super.key});

  /// Versión de la aplicación. Se mantiene en sincronía manualmente con la
  /// declarada en `pubspec.yaml`. Hardcodeada para evitar añadir una
  /// dependencia adicional (`package_info_plus`) solo para mostrarla.
  static const String version = '1.0.0';

  @override
  State<AcercaDeScreen> createState() => _AcercaDeScreenState();
}

class _AcercaDeScreenState extends State<AcercaDeScreen> {
  bool _borrando = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Acerca de')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: Column(
            children: [
              const Spacer(),
              Image.asset(
                'assets/logo_guzmanges.png',
                width: 140,
                height: 140,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              Text(
                'GuzmanGes',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Versión ${AcercaDeScreen.version}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
              const SizedBox(height: 32),
              Text(
                'Aplicación de preventa para representantes comerciales.\n'
                'Proyecto Final de DAM.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_forever),
                  label: Text(_borrando
                      ? 'Borrando…'
                      : 'Borrar todos los datos'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(color: scheme.error),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _borrando ? null : _confirmarYBorrar,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Borra la sesión, los clientes, los productos, los pedidos '
                'y la configuración del servidor. La app volverá a la '
                'pantalla inicial como si se acabase de instalar.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmarYBorrar() async {
    final scheme = Theme.of(context).colorScheme;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded,
            color: scheme.error, size: 40),
        title: const Text('¿Borrar todos los datos?'),
        content: const Text(
          'Se borrará todo lo guardado en este dispositivo (sesión, '
          'clientes, productos, pedidos y configuración del servidor) y '
          'volverás a la pantalla de configuración inicial.\n\n'
          'Esta acción no se puede deshacer.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _borrando = true);

    // Capturamos las referencias a providers y al Navigator ANTES del
    // await, así no dependemos del context tras las operaciones asíncronas.
    final auth = context.read<AuthProvider>();
    final appConfig = context.read<AppConfigProvider>();
    final clientes = context.read<ClientesProvider>();
    final productos = context.read<ProductosProvider>();
    final pedidos = context.read<PedidosProvider>();
    final catalogos = context.read<CatalogosProvider>();
    final navigator = Navigator.of(context);

    try {
      // El ORDEN es crítico para evitar una carrera con la BD:
      //
      // `auth.logout()` dispara su callback `onUsuarioActivoChanged(null)`,
      // que a su vez llama a `pedidos.setUsuarioActivo(null)`. Ese método
      // ejecuta `recargarDesdeLocal()` (lectura asíncrona contra SQLite)
      // SIN que la cadena externa la espere. Si justo después llamamos a
      // `borrarTodo()`, este cierra la BD mientras la lectura sigue en
      // vuelo → DatabaseException(error database_closed).
      //
      // Solución: borrar primero la BD (cierra y la recrea vacía).
      // Cuando luego se haga logout, su recarga interna leerá la BD ya
      // reabierta y devolverá [] sin race.

      // 1. Cerrar y recrear la BD local. Operación rápida.
      await DatabaseHelper.instancia.borrarTodo();

      // 2. Refrescar las listas en memoria contra la BD ya vacía.
      await clientes.recargarDesdeLocal();
      await productos.cargarDesdeLocal();
      await pedidos.recargarDesdeLocal();
      await catalogos.cargarDesdeLocal();

      // 3. Cerrar sesión. Su callback interno leerá la BD vacía sin
      //    problemas y dejará al pedidosProvider sin usuario activo.
      await auth.logout();

      // 4. Limpieza defensiva del almacenamiento seguro por si el logout
      //    dejó algo (es idempotente).
      await TokenStorage().limpiarSesion();

      // 5. Borrar la URL del servidor. `_Raiz` reactivo en main.dart
      //    detecta `estaConfigurado == false` y reemplaza la pantalla
      //    de fondo por ServidorConfigScreen.
      await appConfig.limpiarUrl();
    } catch (e) {
      if (kDebugMode) debugPrint('AcercaDeScreen: error al borrar datos: $e');
      // En caso de fallo parcial dejamos al menos la URL borrada para
      // forzar el reset visual.
      await appConfig.limpiarUrl();
    }

    // Aunque `_Raiz` ya cambió la ruta 0 a ServidorConfigScreen, esta
    // pantalla "Acerca de" sigue pusheada en el Navigator stack: el
    // usuario seguiría viéndola hasta tocar atrás manualmente. Hacemos
    // popUntil para descartarla y dejar al usuario directamente en la
    // pantalla de configuración del servidor.
    if (!mounted) return;
    navigator.popUntil((route) => route.isFirst);
  }
}
