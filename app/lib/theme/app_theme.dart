import 'package:flutter/material.dart';

/// Tema centralizado de la app: define una paleta y unos estilos comunes para
/// que todas las pantallas sean coherentes entre sí. Cambiando la semilla se
/// regenera toda la paleta (Material 3).
class AppTheme {
  AppTheme._();

  /// Color principal del que se deriva toda la paleta.
  static const Color _semilla = Color(0xFFEF6C00); // naranja / ámbar

  /// Tema claro de la aplicación.
  static ThemeData get claro {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _semilla,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
      ),
      // Todos los campos de formulario comparten el mismo borde
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      // Botones principales a ancho completo, con una altura y forma uniformes
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
