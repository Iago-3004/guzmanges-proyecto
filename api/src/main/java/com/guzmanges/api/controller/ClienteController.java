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

import com.guzmanges.api.dto.ClienteResponse;
import com.guzmanges.api.dto.CrearClienteRequest;
import com.guzmanges.api.service.ClienteService;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;

/**
 * Controlador REST de clientes. Requiere autenticación JWT.
 * Permite consultar la cartera de clientes y dar de alta nuevos.
 */
@RestController
@RequestMapping("/clientes")
@RequiredArgsConstructor
public class ClienteController {

    private final ClienteService clienteService;

    /**
     * Lista los clientes.
     *
     * Sin parámetros devuelve únicamente los clientes activos, ordenados por nombre comercial.
     *
     * Con {@code modificadoDesde} en formato ISO-8601 (p. ej. 2026-05-20T15:30:00) devuelve
     * los clientes (activos e inactivos) modificados desde esa fecha. Pensado para
     * sincronizaciones incrementales desde la app móvil: incluye los desactivados para que
     * la app refleje las bajas.
     *
     * @param modificadoDesde fecha de modificación mínima (opcional)
     * @return lista de clientes
     */
    @GetMapping
    public List<ClienteResponse> listar(
            @RequestParam(name = "modificadoDesde", required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime modificadoDesde) {
        if (modificadoDesde == null) {
            return clienteService.listar();
        }
        return clienteService.listarModificadosDesde(modificadoDesde);
    }

    /**
     * Devuelve un cliente por su identificador.
     *
     * @param id identificador del cliente
     * @return el cliente; HTTP 404 si no existe
     */
    @GetMapping("/{id}")
    public ClienteResponse obtener(@PathVariable Long id) {
        return clienteService.obtenerPorId(id);
    }

    /**
     * Da de alta un nuevo cliente, asignado al preventa autenticado.
     *
     * @param request        datos del cliente, validados con Bean Validation
     * @param forzarAlta     si es true, crea el cliente aunque ya exista otro con el mismo CIF
     * @param authentication contexto de seguridad (para identificar al preventa)
     * @return HTTP 201 con el cliente creado; HTTP 400 si los datos no son válidos;
     *         HTTP 409 con la lista de coincidencias si el CIF ya existe y no se fuerza el alta
     */
    @PostMapping
    public ResponseEntity<ClienteResponse> crear(@Valid @RequestBody CrearClienteRequest request,
                                                 @RequestParam(name = "forzarAlta", defaultValue = "false") boolean forzarAlta,
                                                 Authentication authentication) {
        ClienteResponse creado = clienteService.crear(request, authentication.getName(), forzarAlta);
        return ResponseEntity.status(HttpStatus.CREATED).body(creado);
    }
}
