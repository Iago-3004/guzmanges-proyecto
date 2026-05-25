import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'core/storage/config_storage.dart';
import 'core/storage/token_storage.dart';
import 'providers/app_config_provider.dart';
import 'providers/auth_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/servidor_config_screen.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Dependencias compartidas
  final configStorage = ConfigStorage();
  final tokenStorage = TokenStorage();
  final apiClient = ApiClient(tokenStorage);
  final authService = AuthService(apiClient);

  // Si ya hay una URL configurada, se aplica al cliente HTTP antes de arrancar
  final urlGuardada = await configStorage.leerUrlServidor();
  if (urlGuardada != null && urlGuardada.isNotEmpty) {
    apiClient.setBaseUrl(urlGuardada);
  }

  runApp(GuzmanGesApp(
    appConfigProvider: AppConfigProvider(configStorage, apiClient, urlGuardada),
    authProvider: AuthProvider(authService, tokenStorage)..comprobarSesion(),
  ));
}

class GuzmanGesApp extends StatelessWidget {
  final AppConfigProvider appConfigProvider;
  final AuthProvider authProvider;

  const GuzmanGesApp({
    super.key,
    required this.appConfigProvider,
    required this.authProvider,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appConfigProvider),
        ChangeNotifierProvider.value(value: authProvider),
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
