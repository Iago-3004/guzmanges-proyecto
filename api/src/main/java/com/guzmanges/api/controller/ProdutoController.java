package com.guzmanges.api.controller;

import java.time.LocalDateTime;
import java.util.List;

import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.guzmanges.api.dto.ProdutoResponse;
import com.guzmanges.api.service.ProdutoService;

import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;

/**
 * Controlador REST del catálogo de productos. Requiere autenticación JWT.
 *
 * El catálogo es de solo lectura desde la API: los productos se gestionan en Odoo
 * y la app los cachea offline para construir pedidos.
 */
@RestController
@RequestMapping("/productos")
@RequiredArgsConstructor
@Tag(name = "Productos", description = "Catálogo de productos (read-only; gestión en Odoo).")
public class ProdutoController {

    private final ProdutoService produtoService;

    /**
     * Lista los productos.
     *
     * Sin parámetros devuelve todos, ordenados por descripción.
     *
     * Con {@code modificadoDesde} en formato ISO-8601 (p. ej. 2026-05-20T15:30:00) devuelve
     * los productos modificados desde esa fecha. Pensado para sincronizaciones incrementales
     * desde la app móvil.
     *
     * @param modificadoDesde fecha de modificación mínima (opcional)
     * @return lista de productos
     */
    @GetMapping
    public List<ProdutoResponse> listar(
            @RequestParam(name = "modificadoDesde", required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime modificadoDesde) {
        if (modificadoDesde == null) {
            return produtoService.listar();
        }
        return produtoService.listarModificadosDesde(modificadoDesde);
    }

    /**
     * Devuelve un producto por su identificador.
     *
     * @param id identificador del producto
     * @return el producto; HTTP 404 si no existe
     */
    @GetMapping("/{id}")
    public ProdutoResponse obtener(@PathVariable Long id) {
        return produtoService.obtenerPorId(id);
    }
}
