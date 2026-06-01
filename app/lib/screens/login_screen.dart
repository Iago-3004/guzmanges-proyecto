import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

/// Pantalla de inicio de sesión.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usuarioCtrl = TextEditingController();
  final _contrasenaCtrl = TextEditingController();
  bool _ocultarContrasena = true;

  @override
  void dispose() {
    _usuarioCtrl.dispose();
    _contrasenaCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;
    // El resultado se refleja en AuthProvider: si falla, AuthProvider.error
    // se muestra como banner fijo en esta misma pantalla.
    await context
        .read<AuthProvider>()
        .login(_usuarioCtrl.text.trim(), _contrasenaCtrl.text);
  }

  /// Banner fijo de aviso (errores de login o sesión caducada). Más visible que
  /// un SnackBar: permanece hasta que el usuario inicia sesión correctamente.
  Widget _bannerAviso(BuildContext context, String mensaje) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: cs.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(mensaje, style: TextStyle(color: cs.onErrorContainer)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final mensaje = auth.error ??
        (auth.sesionCaducada
            ? 'Tu sesión ha caducado. Vuelve a iniciar sesión.'
            : null);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (mensaje != null) _bannerAviso(context, mensaje),
                  Image.asset(
                    'assets/logo_guzmanges.png',
                    width: 120,
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 8),
                  Text('GuzmanGes',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _usuarioCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Usuario',
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Introduce el usuario'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _contrasenaCtrl,
                    obscureText: _ocultarContrasena,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(_ocultarContrasena
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () => setState(
                            () => _ocultarContrasena = !_ocultarContrasena),
                      ),
                    ),
                    onFieldSubmitted: (_) => _enviar(),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Introduce la contraseña'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: auth.cargando ? null : _enviar,
                      child: auth.cargando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Iniciar sesión'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
