package com.guzmanges.api.exception;

/**
 * Indica que un usuario no se puede eliminar por algún motivo de integridad
 * o de seguridad operativa. Lo lanza el service y lo traduce a HTTP 409 el
 * {@code GlobalExceptionHandler}, devolviendo además los contadores de
 * clientes y pedidos asociados para que el ADMIN entienda por qué.
 *
 * Motivos posibles:
 * <ul>
 *   <li>El usuario tiene clientes o pedidos asociados.</li>
 *   <li>Es el último usuario con rol ADMIN (eliminarlo dejaría el sistema
 *       sin acceso administrativo).</li>
 *   <li>Es el propio usuario que está autenticado (evita que un ADMIN se
 *       autoborre de su sesión activa).</li>
 * </ul>
 */
public class UsuarioNoEliminableException extends RuntimeException {

    private final long clientesAsociados;
    private final long pedidosAsociados;

    public UsuarioNoEliminableException(String mensaje, long clientesAsociados, long pedidosAsociados) {
        super(mensaje);
        this.clientesAsociados = clientesAsociados;
        this.pedidosAsociados = pedidosAsociados;
    }

    public long getClientesAsociados() {
        return clientesAsociados;
    }

    public long getPedidosAsociados() {
        return pedidosAsociados;
    }
}
