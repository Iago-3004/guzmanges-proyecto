import 'cliente.dart' show EstadoSync;
import 'linea_pedido.dart';

/// Estado de negocio del pedido. Refleja el ciclo de vida tal y como lo ve
/// el preventa, y coincide con el enum del backend.
enum EstadoPedido {
  /// Capturado en la app y todavía no confirmado por Odoo. El comercial
  /// puede borrarlo y, mientras esté así, no aparece como venta real.
  borrador('BORRADOR'),

  /// Odoo lo aceptó como sale.order confirmado. Los totales son los
  /// definitivos calculados con la posición fiscal del cliente.
  confirmado('CONFIRMADO'),

  /// Anulado: queda en el histórico pero no cuenta como venta. La app no
  /// permite anular pedidos (lo decide Odoo), solo refleja el estado.
  anulado('ANULADO');

  /// Valor textual tal como lo usan el backend y SQLite.
  final String nombreBackend;

  const EstadoPedido(this.nombreBackend);

  /// Convierte el valor textual del backend al enum correspondiente.
  /// Si el valor no se reconoce devuelve [borrador] como fallback defensivo.
  static EstadoPedido desdeBackend(String? nombre) {
    if (nombre == null) return EstadoPedido.borrador;
    return EstadoPedido.values.firstWhere(
      (e) => e.nombreBackend == nombre,
      orElse: () => EstadoPedido.borrador,
    );
  }
}

/// Pedido guardado en SQLite, capturado en la app y/o sincronizado con el
/// servidor.
///
/// Mantiene la **identidad dual** que ya usan los clientes: [idLocal] es un
/// UUID generado en el móvil y siempre presente; [idServidor] llega del
/// backend, y es null mientras el pedido esté pendiente de subir.
///
/// El pedido referencia al cliente por [clienteIdLocal] (UUID), no por
/// [clienteIdServidor]. Esto permite capturar un pedido para un cliente
/// recién dado de alta offline (todavía sin id de servidor): cuando el
/// cliente se sincronice y reciba su id, el pedido podrá resolver el
/// `clienteId` en el momento del envío.
class Pedido {
  /// UUID v4 generado en la app.
  final String idLocal;

  /// Id del pedido en el servidor. Null mientras esté pendiente de subir.
  final int? idServidor;

  /// Id en Odoo. Solo informativo; lo asigna el backend tras confirmar.
  final String? idOdoo;

  /// Número de pedido asignado por Odoo (p. ej. "S00042"). Null mientras
  /// no se haya confirmado en Odoo.
  final String? numero;

  /// Fecha en la que se capturó el pedido. Para los pedidos creados en la
  /// app es el momento del alta; para los traídos del servidor es la fecha
  /// que tenga en MySQL/Odoo.
  final DateTime fecha;

  /// UUID local del cliente al que pertenece el pedido. FK lógica, no
  /// estricta a nivel SQL (el chequeo se hace al construir/cargar).
  final String clienteIdLocal;

  /// Id del cliente en el servidor cuando ya está sincronizado. Solo
  /// informativo: la referencia "viva" siempre es [clienteIdLocal].
  final int? clienteIdServidor;

  /// Nombre del cliente, denormalizado para pintar la lista sin un JOIN.
  /// Se rellena en el momento del alta y se refresca al sincronizar.
  final String clienteNombre;

  /// Líneas del pedido. Se cargan/persisten en transacción junto con la
  /// cabecera. La lista puede estar vacía en pedidos recién instanciados
  /// que se rellenarán antes de guardar.
  final List<LineaPedido> lineas;

  /// Suma de bases imponibles (precio × cantidad), sin impuestos.
  final double totalBase;

  /// Suma del importe de IVA del pedido.
  final double totalIva;

  /// Suma del importe del recargo de equivalencia del pedido.
  final double totalRE;

  /// Total final con impuestos.
  final double total;

  final EstadoPedido estadoPedido;
  final EstadoSync estadoSync;

  /// Mensaje legible del último error al intentar sincronizar, si lo hubo.
  /// Cubre tanto fallos de red como el caso "esperando a que se sincronice
  /// el cliente": en ese caso el mensaje lo explica al usuario.
  final String? mensajeError;

  final DateTime actualizadoEn;
  final DateTime creadoEn;

  const Pedido({
    required this.idLocal,
    this.idServidor,
    this.idOdoo,
    this.numero,
    required this.fecha,
    required this.clienteIdLocal,
    this.clienteIdServidor,
    required this.clienteNombre,
    this.lineas = const [],
    this.totalBase = 0.0,
    this.totalIva = 0.0,
    this.totalRE = 0.0,
    this.total = 0.0,
    required this.estadoPedido,
    required this.estadoSync,
    this.mensajeError,
    required this.actualizadoEn,
    required this.creadoEn,
  });

  /// Construye un pedido a partir del JSON devuelto por `GET /pedidos` o
  /// `POST /pedidos`. [idLocal] y [clienteIdLocal] los aporta quien llama:
  ///  - [idLocal]: el UUID que ya tenía la fila local equivalente, o uno
  ///    nuevo si es la primera vez que se ve el pedido.
  ///  - [clienteIdLocal]: el UUID local del cliente, resuelto buscando por
  ///    `clienteIdServidor` en SQLite.
  ///
  /// Las líneas se construyen aparte (también necesitan sus propios UUIDs):
  /// se reciben aquí ya armadas para que el modelo quede consistente.
  factory Pedido.desdeServidor(
    Map<String, dynamic> json, {
    required String idLocal,
    required String clienteIdLocal,
    required List<LineaPedido> lineas,
    DateTime? creadoEn,
  }) {
    final ahora = DateTime.now();
    final cliente = json['cliente'] as Map<String, dynamic>;
    return Pedido(
      idLocal: idLocal,
      idServidor: json['id'] as int?,
      idOdoo: json['idOdoo'] as String?,
      numero: json['numero'] as String?,
      fecha: DateTime.parse(json['fecha'] as String),
      clienteIdLocal: clienteIdLocal,
      clienteIdServidor: cliente['id'] as int?,
      clienteNombre: (cliente['razonSocial'] as String?) ?? '',
      lineas: lineas,
      totalBase: (json['totalBase'] as num?)?.toDouble() ?? 0.0,
      totalIva: (json['totalIva'] as num?)?.toDouble() ?? 0.0,
      totalRE: (json['totalRE'] as num?)?.toDouble() ?? 0.0,
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      estadoPedido: EstadoPedido.desdeBackend(json['estadoPedido'] as String?),
      estadoSync: EstadoSync.sincronizado,
      mensajeError: null,
      actualizadoEn: ahora,
      creadoEn: creadoEn ?? ahora,
    );
  }

  /// Reconstruye el pedido desde una fila de SQLite. Las líneas se cargan
  /// aparte (con la tabla `lineas_pedido` filtrada por `pedido_id_local`) y
  /// se pasan aquí ya construidas.
  factory Pedido.fromMap(
    Map<String, Object?> map, {
    required List<LineaPedido> lineas,
  }) {
    return Pedido(
      idLocal: map['id_local'] as String,
      idServidor: map['id_servidor'] as int?,
      idOdoo: map['id_odoo'] as String?,
      numero: map['numero'] as String?,
      fecha: DateTime.fromMillisecondsSinceEpoch(map['fecha'] as int),
      clienteIdLocal: map['cliente_id_local'] as String,
      clienteIdServidor: map['cliente_id_servidor'] as int?,
      clienteNombre: map['cliente_nombre'] as String,
      lineas: lineas,
      totalBase: ((map['total_base'] as num?) ?? 0).toDouble(),
      totalIva: ((map['total_iva'] as num?) ?? 0).toDouble(),
      totalRE: ((map['total_re'] as num?) ?? 0).toDouble(),
      total: ((map['total'] as num?) ?? 0).toDouble(),
      estadoPedido: EstadoPedido.desdeBackend(map['estado_pedido'] as String?),
      estadoSync: EstadoSync.desdeBackend(map['estado_sync'] as String?),
      mensajeError: map['mensaje_error'] as String?,
      actualizadoEn:
          DateTime.fromMillisecondsSinceEpoch(map['actualizado_en'] as int),
      creadoEn: DateTime.fromMillisecondsSinceEpoch(map['creado_en'] as int),
    );
  }

  /// Serializa la cabecera del pedido para guardar en SQLite. Las líneas
  /// se persisten aparte en la tabla `lineas_pedido`.
  Map<String, Object?> toMap() {
    return {
      'id_local': idLocal,
      'id_servidor': idServidor,
      'id_odoo': idOdoo,
      'numero': numero,
      'fecha': fecha.millisecondsSinceEpoch,
      'cliente_id_local': clienteIdLocal,
      'cliente_id_servidor': clienteIdServidor,
      'cliente_nombre': clienteNombre,
      'total_base': totalBase,
      'total_iva': totalIva,
      'total_re': totalRE,
      'total': total,
      'estado_pedido': estadoPedido.nombreBackend,
      'estado_sync': estadoSync.nombreBackend,
      'mensaje_error': mensajeError,
      'actualizado_en': actualizadoEn.millisecondsSinceEpoch,
      'creado_en': creadoEn.millisecondsSinceEpoch,
    };
  }
}
