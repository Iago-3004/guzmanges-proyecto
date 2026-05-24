package com.guzmanges.api.controller;

import java.util.List;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
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
     * Lista las condiciones de pago activas.
     *
     * @return lista de condiciones de pago
     */
    @GetMapping
    public List<CondicionPagoResponse> listar() {
        return condicionPagoService.listar();
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
