package com.guzmanges.api.controller;

import java.time.LocalDateTime;
import java.util.List;

import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.guzmanges.api.dto.CrearPedidoRequest;
import com.guzmanges.api.dto.PedidoResponse;
import com.guzmanges.api.service.PedidoService;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;

/**
 * Controlador REST de pedidos. Requiere autenticación JWT.
 *
 * Un usuario PREVENTA solo ve y crea sus propios pedidos; un ADMIN puede ver
 * todos. El filtro por preventa se aplica en el servicio según el contexto de
 * seguridad.
 */
@RestController
@RequestMapping("/pedidos")
@RequiredArgsConstructor
public class PedidoController {

    private final PedidoService pedidoService;

    /**
     * Lista los pedidos visibles para el usuario autenticado.
     *
     * Sin parámetros devuelve los pedidos del preventa (o todos si es ADMIN),
     * ordenados de más reciente a más antiguo.
     *
     * Con {@code modificadoDesde} en formato ISO-8601 (p. ej. 2026-05-20T15:30:00)
     * devuelve los pedidos modificados desde esa fecha. Pensado para
     * sincronizaciones incrementales desde la app.
     *
     * @param modificadoDesde fecha de modificación mínima (opcional)
     * @param authentication  contexto de seguridad
     * @return lista de pedidos visibles para el usuario
     */
    @GetMapping
    public List<PedidoResponse> listar(
            @RequestParam(name = "modificadoDesde", required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime modificadoDesde,
            Authentication authentication) {
        if (modificadoDesde == null) {
            return pedidoService.listar(authentication);
        }
        return pedidoService.listarModificadosDesde(modificadoDesde, authentication);
    }

    /**
     * Devuelve un pedido por su identificador. Un preventa solo puede ver los
     * suyos: si pide uno ajeno se responde 404 (sin distinguir entre "no existe"
     * y "no es tuyo", para no filtrar información).
     *
     * @param id             identificador del pedido
     * @param authentication contexto de seguridad
     * @return el pedido; HTTP 404 si no existe o no pertenece al usuario
     */
    @GetMapping("/{id}")
    public PedidoResponse obtener(@PathVariable Long id, Authentication authentication) {
        return pedidoService.obtenerPorId(id, authentication);
    }

    /**
     * Da de alta un pedido nuevo desde la app. El pedido queda en BORRADOR y
     * PENDENTE; el envío a Odoo lo hace el scheduler periódico (o el manual
     * desde {@code /sync/**}).
     *
     * @param request        datos del pedido (cliente y líneas), validados
     * @param authentication contexto de seguridad (para asignar el preventa)
     * @return HTTP 201 con el pedido creado y los totales provisionales
     */
    @PostMapping
    public ResponseEntity<PedidoResponse> crear(@Valid @RequestBody CrearPedidoRequest request,
                                                Authentication authentication) {
        PedidoResponse creado = pedidoService.crear(request, authentication);
        return ResponseEntity.status(HttpStatus.CREATED).body(creado);
    }
}
