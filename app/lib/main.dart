import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/db/dao/catalogos_dao.dart';
import 'core/db/dao/clientes_dao.dart';
import 'core/db/dao/sync_metadata_dao.dart';
import 'core/db/database_helper.dart';
import 'core/network/api_client.dart';
import 'core/storage/config_storage.dart';
import 'core/storage/token_storage.dart';
import 'providers/app_config_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/catalogos_provider.dart';
import 'providers/clientes_provider.dart';
import 'providers/sync_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/servidor_config_screen.dart';
import 'services/auth_service.dart';
import 'services/catalogos_service.dart';
import 'services/clientes_service.dart';
import 'services/sync_clientes_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Base de datos local (SQLite). Se abre antes de arrancar la app para que
  // cualquier provider o servicio pueda usarla sin comprobaciones extra.
  await DatabaseHelper.instancia.abrir();

  // Dependencias compartidas
  final configStorage = ConfigStorage();
  final tokenStorage = TokenStorage();
  final apiClient = ApiClient(tokenStorage);
  final authService = AuthService(apiClient);
  final catalogosService = CatalogosService(apiClient);
  final catalogosDao = CatalogosDao();
  final clientesService = ClientesService(apiClient);
  final clientesDao = ClientesDao();
  final syncMetadataDao = SyncMetadataDao();
  final syncClientesService = SyncClientesService(apiClient, clientesDao);

  // Si ya hay una URL configurada, se aplica al cliente HTTP antes de arrancar
  final urlGuardada = await configStorage.leerUrlServidor();
  if (urlGuardada != null && urlGuardada.isNotEmpty) {
    apiClient.setBaseUrl(urlGuardada);
  }

  final catalogosProvider =
      CatalogosProvider(catalogosService, catalogosDao)..cargarDesdeLocal();
  final clientesProvider =
      ClientesProvider(clientesService, clientesDao)..recargarDesdeLocal();
  final syncProvider = SyncProvider(
    catalogosProvider,
    clientesProvider,
    syncClientesService,
    syncMetadataDao,
  );

  runApp(GuzmanGesApp(
    appConfigProvider: AppConfigProvider(configStorage, apiClient, urlGuardada),
    authProvider: AuthProvider(authService, tokenStorage)..comprobarSesion(),
    catalogosProvider: catalogosProvider,
    clientesProvider: clientesProvider,
    syncProvider: syncProvider,
  ));
}

class GuzmanGesApp extends StatelessWidget {
  final AppConfigProvider appConfigProvider;
  final AuthProvider authProvider;
  final CatalogosProvider catalogosProvider;
  final ClientesProvider clientesProvider;
  final SyncProvider syncProvider;

  const GuzmanGesApp({
    super.key,
    required this.appConfigProvider,
    required this.authProvider,
    required this.catalogosProvider,
    required this.clientesProvider,
    required this.syncProvider,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appConfigProvider),
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: catalogosProvider),
        ChangeNotifierProvider.value(value: clientesProvider),
        ChangeNotifierProvider.value(value: syncProvider),
      ],
      child: MaterialApp(
        title: 'GuzmanGes',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.claro,
        home: const _Raiz(),
      ),
    );
  }
}

/// Decide la pantalla inicial: configuración del servidor, login o home.
class _Raiz extends StatelessWidget {
  const _Raiz();

  @override
  Widget build(BuildContext context) {
    final estaConfigurado = context.watch<AppConfigProvider>().estaConfigurado;
    if (!estaConfigurado) {
      return const ServidorConfigScreen();
    }

    final estadoAuth = context.watch<AuthProvider>().estado;
    switch (estadoAuth) {
      case EstadoAuth.desconocido:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case EstadoAuth.autenticado:
        return const HomeScreen();
      case EstadoAuth.noAutenticado:
        return const LoginScreen();
    }
  }
}
