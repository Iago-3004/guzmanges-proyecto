/// Tablas legales españolas del recargo de equivalencia.
///
/// El recargo de equivalencia es un impuesto adicional al IVA que un proveedor
/// repercute a los clientes minoristas autónomos. Los tipos están fijados por
/// la ley del IVA y solo cambian en reformas fiscales; por eso se mantienen
/// aquí como tabla cerrada, en vez de pedirlos al servidor.
///
/// La fuente de verdad definitiva la sigue teniendo Odoo: cuando un pedido se
/// confirma, Odoo aplica el motor de impuestos completo (que conoce la posición
/// fiscal del cliente y sus excepciones) y devuelve los totales reales, que el
/// backend baja a la app. Esta calculadora se usa solo para la previsualización
/// provisional en la app y para que el backend recalcule de forma consistente
/// antes de enviar el pedido a Odoo.
class CalculadoraRE {
  CalculadoraRE._();

  /// Devuelve el tipo de recargo de equivalencia (en porcentaje) que corresponde
  /// a un tipo de IVA dado.
  ///
  /// Los tipos cubiertos son los habituales en venta minorista; tipos atípicos
  /// (p. ej. 1.75 % para tabaco) no se contemplan: si el IVA recibido no figura
  /// en la tabla, devuelve 0 y el cálculo definitivo lo hará Odoo al recibir el
  /// pedido. La comparación se hace redondeando a entero para evitar problemas
  /// de precisión con dobles que provengan de la sincronización (21.00 vs 21.0).
  ///
  /// Ejemplos:
  /// - `recargoParaIva(21.0)` → `5.2`
  /// - `recargoParaIva(10.0)` → `1.4`
  /// - `recargoParaIva(7.5)`  → `0.0` (no figura en la tabla)
  static double recargoParaIva(double iva) {
    return switch (iva.round()) {
      21 => 5.2,
      10 => 1.4,
      4 => 0.5,
      _ => 0.0,
    };
  }
}
