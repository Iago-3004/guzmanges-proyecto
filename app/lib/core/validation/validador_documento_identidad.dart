/// Valida la estructura de un documento de identidad español: NIF, NIE o CIF.
///
/// Acepta indistintamente los tres formatos porque desde el formulario de alta
/// de clientes el comercial puede introducir cualquiera (autónomo con NIF,
/// extranjero con NIE, empresa con CIF) y Odoo los acepta todos. La validación
/// es estructural: comprueba la longitud, los caracteres permitidos y el
/// dígito/letra de control. Si pasa, Odoo lo dará por bueno; si falla,
/// rechazaría el alta y bloquearía la sincronización.
class ValidadorDocumentoIdentidad {
  ValidadorDocumentoIdentidad._();

  /// Letras de control del NIF/NIE, indexadas por (número mod 23).
  static const String _letrasNif = 'TRWAGMYFPDXBNJZSQVHLCKE';

  /// Letras de control del CIF, indexadas por el dígito calculado (0..9).
  static const String _letrasCif = 'JABCDEFGHI';

  /// Primera letra del CIF cuya cifra de control debe ser **letra** (PQRSNW).
  static const String _cifControlLetra = 'PQRSNW';

  /// Primera letra del CIF cuya cifra de control debe ser **dígito** (ABEH).
  static const String _cifControlDigito = 'ABEH';

  /// Primeras letras válidas de un CIF (entidades jurídicas).
  static const String _cifLetrasIniciales = 'ABCDEFGHJNPQRSUVW';

  /// Normaliza un documento: lo pasa a mayúsculas y elimina espacios y guiones.
  /// Útil tanto para validar como para guardar la versión "limpia" antes de
  /// enviarla al backend, de modo que la comparación con CIF/NIF de Odoo sea
  /// consistente.
  static String normalizar(String valor) {
    return valor.trim().toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  }

  /// Mensaje único para cualquier fallo de validación cuando la longitud
  /// SÍ es la correcta (9 caracteres). Se usa para no dar pistas concretas
  /// (letra esperada, primera letra inválida, etc.) que pueden ser ruido
  /// para el usuario; con que sepa que no es válido le basta para revisarlo.
  static const String _mensajeInvalido = 'El CIF/NIF no es válido';

  /// Valida un NIF/NIE/CIF. Devuelve `null` si es correcto, o un mensaje de
  /// error en castellano si no lo es. El mensaje está pensado para mostrarse
  /// directamente bajo el campo del formulario.
  ///
  /// La diferenciación es deliberadamente mínima:
  /// - Si está vacío, se pide rellenarlo.
  /// - Si la longitud no es 9, se indica el formato esperado para guiar
  ///   al usuario que aún está escribiendo.
  /// - En cualquier otro caso (longitud correcta pero estructura, letra o
  ///   dígito de control inválidos) se devuelve un mensaje genérico.
  static String? validar(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'El CIF/NIF es obligatorio';
    }
    final v = normalizar(valor);
    if (v.length != 9) {
      return 'Debe tener 9 caracteres (NIF, NIE o CIF)';
    }
    final primero = v[0];
    if (RegExp(r'[0-9]').hasMatch(primero)) {
      return _validarNif(v);
    }
    if ('XYZ'.contains(primero)) {
      return _validarNie(v);
    }
    if (_cifLetrasIniciales.contains(primero)) {
      return _validarCif(v);
    }
    return _mensajeInvalido;
  }

  static String? _validarNif(String v) {
    if (!RegExp(r'^\d{8}[A-Z]$').hasMatch(v)) {
      return _mensajeInvalido;
    }
    final numero = int.parse(v.substring(0, 8));
    final letraEsperada = _letrasNif[numero % 23];
    if (letraEsperada != v[8]) {
      return _mensajeInvalido;
    }
    return null;
  }

  static String? _validarNie(String v) {
    if (!RegExp(r'^[XYZ]\d{7}[A-Z]$').hasMatch(v)) {
      return _mensajeInvalido;
    }
    const equivalentes = {'X': '0', 'Y': '1', 'Z': '2'};
    final numero = int.parse(equivalentes[v[0]]! + v.substring(1, 8));
    final letraEsperada = _letrasNif[numero % 23];
    if (letraEsperada != v[8]) {
      return _mensajeInvalido;
    }
    return null;
  }

  static String? _validarCif(String v) {
    if (!RegExp(r'^[A-Z]\d{7}[\dA-J]$').hasMatch(v)) {
      return _mensajeInvalido;
    }
    final letraInicial = v[0];
    final centro = v.substring(1, 8);
    final control = v[8];

    // Suma: posiciones impares (1-indexadas: 1, 3, 5, 7 → 0, 2, 4, 6 en
    // 0-indexado) se duplican y se suman los dígitos del resultado; las
    // posiciones pares (2, 4, 6 → 1, 3, 5) se suman tal cual.
    int suma = 0;
    for (int i = 0; i < 7; i++) {
      final d = int.parse(centro[i]);
      if (i % 2 == 0) {
        final doblado = d * 2;
        suma += doblado > 9 ? doblado - 9 : doblado;
      } else {
        suma += d;
      }
    }
    final ultimo = suma % 10;
    final digitoControl = ultimo == 0 ? 0 : 10 - ultimo;
    final letraControl = _letrasCif[digitoControl];
    final digitoControlChar = digitoControl.toString();

    if (_cifControlLetra.contains(letraInicial)) {
      if (control != letraControl) return _mensajeInvalido;
    } else if (_cifControlDigito.contains(letraInicial)) {
      if (control != digitoControlChar) return _mensajeInvalido;
    } else {
      if (control != digitoControlChar && control != letraControl) {
        return _mensajeInvalido;
      }
    }
    return null;
  }
}
