import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/validation/validador_documento_identidad.dart';
import '../../dto/crear_cliente_request.dart';
import '../../models/condicion_pago.dart';
import '../../models/modo_pago.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalogos_provider.dart';
import '../../providers/clientes_provider.dart';
import '../../widgets/dialogo_coincidencias_cif.dart';

/// Formulario de alta de un cliente nuevo.
///
/// Al guardar, el cliente queda en SQLite con `estadoSync = PENDENTE` y
/// pendiente de envío al servidor en la próxima sincronización. Los
/// catálogos de los selectores se leen del [CatalogosProvider] (caché
/// local), por lo que el formulario funciona también sin conexión.
class ClienteFormScreen extends StatefulWidget {
  const ClienteFormScreen({super.key});

  @override
  State<ClienteFormScreen> createState() => _ClienteFormScreenState();
}

class _ClienteFormScreenState extends State<ClienteFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controladores de texto
  final _nombreComercialCtrl = TextEditingController();
  final _razonSocialCtrl = TextEditingController();
  final _cifCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _localidadCtrl = TextEditingController();
  final _codigoPostalCtrl = TextEditingController();
  final _provinciaCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _movilCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  // Selecciones de catálogos
  int? _modoPagoId;
  int? _condicionPagoId;

  bool _guardando = false;

  /// Modo de autovalidación del formulario. Empieza como [disabled] para no
  /// molestar mientras el usuario rellena los campos por primera vez. La
  /// primera vez que pulsa "Guardar" con errores, se cambia a
  /// [onUserInteraction] para que los errores se actualicen al escribir.
  AutovalidateMode _modoValidacion = AutovalidateMode.disabled;

  @override
  void dispose() {
    _nombreComercialCtrl.dispose();
    _razonSocialCtrl.dispose();
    _cifCtrl.dispose();
    _direccionCtrl.dispose();
    _localidadCtrl.dispose();
    _codigoPostalCtrl.dispose();
    _provinciaCtrl.dispose();
    _telefonoCtrl.dispose();
    _movilCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalogos = context.watch<CatalogosProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo cliente')),
      body: Form(
        key: _formKey,
        autovalidateMode: _modoValidacion,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            _Seccion(
              titulo: 'Identificación',
              icono: Icons.badge_outlined,
              children: [
                _campoTexto(
                  controller: _nombreComercialCtrl,
                  label: 'Nombre comercial *',
                  validator: (v) =>
                      _requerido(v, 'El nombre comercial es obligatorio'),
                  textCapitalization: TextCapitalization.words,
                ),
                _campoTexto(
                  controller: _razonSocialCtrl,
                  label: 'Razón social *',
                  validator: (v) =>
                      _requerido(v, 'La razón social es obligatoria'),
                  textCapitalization: TextCapitalization.words,
                ),
                _campoTexto(
                  controller: _cifCtrl,
                  label: 'CIF/NIF *',
                  validator: ValidadorDocumentoIdentidad.validar,
                  textCapitalization: TextCapitalization.characters,
                ),
              ],
            ),
            _Seccion(
              titulo: 'Dirección',
              icono: Icons.location_on_outlined,
              children: [
                _campoTexto(
                  controller: _direccionCtrl,
                  label: 'Dirección *',
                  validator: (v) =>
                      _requerido(v, 'La dirección es obligatoria'),
                  textCapitalization: TextCapitalization.sentences,
                ),
                _campoTexto(
                  controller: _localidadCtrl,
                  label: 'Localidad *',
                  validator: (v) =>
                      _requerido(v, 'La localidad es obligatoria'),
                  textCapitalization: TextCapitalization.words,
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _campoTexto(
                        controller: _codigoPostalCtrl,
                        label: 'C. postal *',
                        validator: (v) =>
                            _requerido(v, 'El código postal es obligatorio'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: _campoTexto(
                        controller: _provinciaCtrl,
                        label: 'Provincia *',
                        validator: (v) =>
                            _requerido(v, 'La provincia es obligatoria'),
                        textCapitalization: TextCapitalization.words,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            _Seccion(
              titulo: 'Contacto',
              icono: Icons.contact_phone_outlined,
              children: [
                _campoTexto(
                  controller: _telefonoCtrl,
                  label: 'Teléfono',
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9 +\-()]')),
                    LengthLimitingTextInputFormatter(20),
                  ],
                ),
                _campoTexto(
                  controller: _movilCtrl,
                  label: 'Móvil',
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9 +\-()]')),
                    LengthLimitingTextInputFormatter(20),
                  ],
                ),
                _campoTexto(
                  controller: _emailCtrl,
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                  validator: _validarEmail,
                ),
              ],
            ),
            _Seccion(
              titulo: 'Condiciones de pago',
              icono: Icons.payments_outlined,
              children: [
                _dropdownModo(catalogos.modos),
                _dropdownCondicion(catalogos.condiciones),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_guardando ? 'Guardando…' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Widgets auxiliares
  // ---------------------------------------------------------------------------

  Widget _campoTexto({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        validator: validator,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
      ),
    );
  }

  Widget _dropdownModo(List<ModoPago> modos) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<int?>(
        initialValue: _modoPagoId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Modo de pago',
          floatingLabelBehavior: FloatingLabelBehavior.always,
          border: OutlineInputBorder(gapPadding: 8),
          enabledBorder: OutlineInputBorder(gapPadding: 8),
          focusedBorder: OutlineInputBorder(gapPadding: 8),
        ),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('(Sin asignar)')),
          for (final m in modos)
            DropdownMenuItem<int?>(value: m.id, child: Text(m.descripcion)),
        ],
        onChanged: (v) => setState(() => _modoPagoId = v),
      ),
    );
  }

  Widget _dropdownCondicion(List<CondicionPago> condiciones) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<int?>(
        initialValue: _condicionPagoId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Condición de pago',
          floatingLabelBehavior: FloatingLabelBehavior.always,
          border: OutlineInputBorder(gapPadding: 8),
          enabledBorder: OutlineInputBorder(gapPadding: 8),
          focusedBorder: OutlineInputBorder(gapPadding: 8),
        ),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('(Sin asignar)')),
          for (final c in condiciones)
            DropdownMenuItem<int?>(value: c.id, child: Text(c.descripcion)),
        ],
        onChanged: (v) => setState(() => _condicionPagoId = v),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Validadores
  // ---------------------------------------------------------------------------

  String? _requerido(String? valor, String mensaje) {
    if (valor == null || valor.trim().isEmpty) return mensaje;
    return null;
  }

  String? _validarEmail(String? valor) {
    if (valor == null || valor.trim().isEmpty) return null; // opcional
    final regex = RegExp(r'^[\w.\-+]+@[\w.\-]+\.[A-Za-z]{2,}$');
    if (!regex.hasMatch(valor.trim())) {
      return 'Email con formato no válido';
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Acción "Guardar"
  // ---------------------------------------------------------------------------

  Future<void> _guardar() async {
    // Tras el primer intento, los errores se actualizan al escribir, así el
    // usuario ve los campos pasar de rojo a OK en tiempo real al corregirlos.
    if (_modoValidacion == AutovalidateMode.disabled) {
      setState(() => _modoValidacion = AutovalidateMode.onUserInteraction);
    }
    if (!_formKey.currentState!.validate()) {
      // El campo con error puede haber quedado fuera de la zona visible si el
      // teclado oculta parte del formulario. Avisamos con un SnackBar para que
      // el usuario sepa por qué no se guardó aunque no vea el campo señalado.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: const Text('Hay campos con errores. Revísalos antes de guardar.'),
        ),
      );
      return;
    }

    setState(() => _guardando = true);
    try {
      final catalogos = context.read<CatalogosProvider>();
      final auth = context.read<AuthProvider>();
      final clientesProvider = context.read<ClientesProvider>();

      final cifNormalizado =
          ValidadorDocumentoIdentidad.normalizar(_cifCtrl.text);

      // Comprobación local de CIF duplicado: si ya existe alguno en SQLite con
      // el mismo CIF, mostramos un diálogo y dejamos que el usuario decida.
      // Si confirma, marcamos el cliente con `forzarEnvio = true` para que al
      // subirlo no se le vuelva a preguntar la misma confirmación al recibir
      // un 409 del servidor.
      bool forzarEnvio = false;
      final coincidencias =
          await clientesProvider.buscarCoincidenciasPorCif(cifNormalizado);
      if (coincidencias.isNotEmpty) {
        if (!mounted) return;
        final forzar = await DialogoCoincidenciasCif.mostrar(
          context,
          coincidencias: coincidencias,
          cif: cifNormalizado,
        );
        if (!forzar) {
          // El usuario canceló: no guardamos nada.
          if (mounted) setState(() => _guardando = false);
          return;
        }
        forzarEnvio = true;
      }

      final descModo = _buscarDescripcion(
          catalogos.modos.map((m) => (m.id, m.descripcion)), _modoPagoId);
      final descCondicion = _buscarDescripcion(
          catalogos.condiciones.map((c) => (c.id, c.descripcion)),
          _condicionPagoId);

      final req = CrearClienteRequest(
        nombreComercial: _nombreComercialCtrl.text.trim(),
        razonSocial: _razonSocialCtrl.text.trim(),
        cif: cifNormalizado,
        direccion: _opcional(_direccionCtrl),
        localidad: _opcional(_localidadCtrl),
        codigoPostal: _opcional(_codigoPostalCtrl),
        provincia: _opcional(_provinciaCtrl),
        telefono: _opcional(_telefonoCtrl),
        movil: _opcional(_movilCtrl),
        email: _opcional(_emailCtrl),
        modoPagoId: _modoPagoId,
        condicionPagoId: _condicionPagoId,
      );

      await clientesProvider.crearCliente(
        req,
        modoPagoDescripcion: descModo,
        condicionPagoDescripcion: descCondicion,
        comercial: auth.nombreUsuario,
        forzarEnvio: forzarEnvio,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: const Text(
              'Cliente guardado. Pulsa Sincronizar para enviarlo al servidor.'),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text(
              'Error al guardar: ${e.toString().replaceFirst('Exception: ', '')}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  String? _opcional(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  /// Busca la descripción asociada a [id] dentro de una lista de tuplas
  /// `(id, descripcion)`. Devuelve null si no se encuentra o si [id] es null.
  String? _buscarDescripcion(Iterable<(int, String)> pares, int? id) {
    if (id == null) return null;
    for (final p in pares) {
      if (p.$1 == id) return p.$2;
    }
    return null;
  }
}

/// Tarjeta de sección del formulario, con icono y título destacados.
class _Seccion extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final List<Widget> children;

  const _Seccion({
    required this.titulo,
    required this.icono,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
