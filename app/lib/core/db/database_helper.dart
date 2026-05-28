import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migraciones.dart';

/// Punto de acceso único a la base de datos local SQLite (`guzmanges.db`).
///
/// Implementa un singleton perezoso: la BD se abre la primera vez que se
/// pide y se reutiliza durante toda la vida de la app. Activa
/// `PRAGMA foreign_keys=ON` en cada apertura para garantizar la integridad
/// referencial entre tablas.
///
/// Las migraciones de esquema se delegan en [Migraciones]; este helper solo
/// se ocupa de la apertura y de invocar `onCreate`/`onUpgrade`.
///
/// Uso típico:
/// ```dart
/// await DatabaseHelper.instancia.abrir();
/// final db = DatabaseHelper.instancia.db;
/// final filas = await db.query('clientes');
/// ```
class DatabaseHelper {
  DatabaseHelper._();

  /// Instancia única del helper.
  static final DatabaseHelper instancia = DatabaseHelper._();

  /// Nombre del fichero de la base de datos local.
  static const String _nombreBd = 'guzmanges.db';

  Database? _db;

  /// Acceso a la instancia abierta. Lanza un [StateError] si aún no se llamó
  /// a [abrir]. Por contrato la BD se abre una sola vez en `main()` antes de
  /// arrancar la app.
  Database get db {
    final actual = _db;
    if (actual == null) {
      throw StateError(
          'La base de datos no está abierta. Llama a DatabaseHelper.instancia.abrir() '
          'antes de usarla (típicamente en main()).');
    }
    return actual;
  }

  /// Abre (o crea si no existe) la base de datos local y aplica las
  /// migraciones necesarias.
  ///
  /// Es seguro llamarla varias veces: la segunda y sucesivas no hacen nada.
  Future<void> abrir() async {
    if (_db != null) return;

    final directorio = await getDatabasesPath();
    final ruta = p.join(directorio, _nombreBd);

    _db = await openDatabase(
      ruta,
      version: Migraciones.versionActual,
      onConfigure: (db) async {
        // Activa la integridad referencial. Sqlite la trae desactivada por defecto.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await Migraciones.aplicar(db, 0, version);
      },
      onUpgrade: (db, viejaVersion, nuevaVersion) async {
        await Migraciones.aplicar(db, viejaVersion, nuevaVersion);
      },
    );

    if (kDebugMode) {
      debugPrint('DatabaseHelper: BD abierta en versión ${Migraciones.versionActual} '
          '(ruta: $ruta)');
    }
  }

  /// Cierra la base de datos. Útil en tests o si se necesita reabrir.
  Future<void> cerrar() async {
    final actual = _db;
    if (actual == null) return;
    await actual.close();
    _db = null;
  }
}
