import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../providers/app_config_provider.dart';

/// Formulario que se muestra solo en la primera ejecución para configurar la
/// URL del servidor. Una vez guardada, la app pasa al login y no vuelve a salir.
class ServidorConfigScreen extends StatefulWidget {
  const ServidorConfigScreen({super.key});

  @override
  State<ServidorConfigScreen> createState() => _ServidorConfigScreenState();
}

class _ServidorConfigScreenState extends State<ServidorConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlCtrl = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  String? _validarUrl(String? valor) {
    final v = valor?.trim() ?? '';
    if (v.isEmpty) return 'Introduce la URL del servidor';
    if (!v.startsWith('http://') && !v.startsWith('https://')) {
      return 'La URL debe empezar por http:// o https://';
    }
    final uri = Uri.tryParse(v);
    if (uri == null || uri.host.isEmpty) return 'La URL no es válida';
    return null;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);

    final messenger = ScaffoldMessenger.of(context);
    try {
      // No basta con guardar la URL: si está mal escrita o el servidor no
      // está corriendo, el usuario se enteraría más tarde en el login con
      // un error genérico. Probamos contra /actuator/health primero.
      await context
          .read<AppConfigProvider>()
          .comprobarYGuardarUrl(_urlCtrl.text);
      // Si todo OK, AppConfigProvider notifica y la app navega automáticamente al login.
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 5),
          content:
              Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración del servidor')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                const Icon(Icons.dns, size: 64),
                const SizedBox(height: 16),
                Text(
                  'Introduce la dirección del servidor de GuzmanGes. '
                  'Solo se pide la primera vez.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _urlCtrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'URL del servidor',
                    hintText: ApiConfig.urlEjemplo,
                    prefixIcon: Icon(Icons.link),
                  ),
                  validator: _validarUrl,
                  onFieldSubmitted: (_) => _guardar(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _guardando ? null : _guardar,
                  child: _guardando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar y continuar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
