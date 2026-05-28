package com.guzmanges.api.controller;

import java.time.LocalDateTime;
import java.util.List;

import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.guzmanges.api.dto.CondicionPagoResponse;
import com.guzmanges.api.service.CondicionPagoService;

import lombok.RequiredArgsConstructor;

/**
 * Controlador REST de condiciones de pago (solo lectura). Requiere autenticación JWT.
 */
@RestController
@RequestMapping("/condiciones-pago")
@RequiredArgsConstructor
public class CondicionPagoController {

    private final CondicionPagoService condicionPagoService;

    /**
     * Lista las condiciones de pago.
     *
     * Sin parámetros devuelve únicamente las activas. Con {@code modificadoDesde} en formato
     * ISO-8601 devuelve las condiciones de pago (activas e inactivas) modificadas desde esa
     * fecha, pensado para sincronizaciones incrementales.
     *
     * @param modificadoDesde fecha de modificación mínima (opcional)
     * @return lista de condiciones de pago
     */
    @GetMapping
    public List<CondicionPagoResponse> listar(
            @RequestParam(name = "modificadoDesde", required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime modificadoDesde) {
        if (modificadoDesde == null) {
            return condicionPagoService.listar();
        }
        return condicionPagoService.listarModificadasDesde(modificadoDesde);
    }

    /**
     * Devuelve una condición de pago por su identificador.
     *
     * @param id identificador de la condición de pago
     * @return la condición de pago; HTTP 404 si no existe
     */
    @GetMapping("/{id}")
    public CondicionPagoResponse obtener(@PathVariable Long id) {
        return condicionPagoService.obtenerPorId(id);
    }
}
