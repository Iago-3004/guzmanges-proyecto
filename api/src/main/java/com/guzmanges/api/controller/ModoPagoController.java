package com.guzmanges.api.controller;

import java.time.LocalDateTime;
import java.util.List;

import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.guzmanges.api.dto.ModoPagoResponse;
import com.guzmanges.api.service.ModoPagoService;

import lombok.RequiredArgsConstructor;

/**
 * Controlador REST de modos de pago (solo lectura). Requiere autenticación JWT.
 */
@RestController
@RequestMapping("/modos-pago")
@RequiredArgsConstructor
public class ModoPagoController {

    private final ModoPagoService modoPagoService;

    /**
     * Lista los modos de pago.
     *
     * Sin parámetros devuelve únicamente los activos. Con {@code modificadoDesde} en formato
     * ISO-8601 devuelve los modos de pago (activos e inactivos) modificados desde esa fecha,
     * pensado para sincronizaciones incrementales.
     *
     * @param modificadoDesde fecha de modificación mínima (opcional)
     * @return lista de modos de pago
     */
    @GetMapping
    public List<ModoPagoResponse> listar(
            @RequestParam(name = "modificadoDesde", required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime modificadoDesde) {
        if (modificadoDesde == null) {
            return modoPagoService.listar();
        }
        return modoPagoService.listarModificadosDesde(modificadoDesde);
    }

    /**
     * Devuelve un modo de pago por su identificador.
     *
     * @param id identificador del modo de pago
     * @return el modo de pago; HTTP 404 si no existe
     */
    @GetMapping("/{id}")
    public ModoPagoResponse obtener(@PathVariable Long id) {
        return modoPagoService.obtenerPorId(id);
    }
}
