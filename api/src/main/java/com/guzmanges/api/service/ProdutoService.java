package com.guzmanges.api.service;

import java.time.LocalDateTime;
import java.util.List;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.guzmanges.api.dto.ProdutoResponse;
import com.guzmanges.api.entity.Produto;
import com.guzmanges.api.exception.ResourceNotFoundException;
import com.guzmanges.api.mapper.ProdutoMapper;
import com.guzmanges.api.repository.ProdutoRepository;

import lombok.RequiredArgsConstructor;

/**
 * Lógica de negocio del catálogo de productos.
 *
 * Los productos son de solo lectura: se gestionan en Odoo y la API los expone
 * para que la app cachee el catálogo en local. No hay altas ni bajas desde la
 * API pública: las modificaciones llegan vía sincronización con Odoo.
 */
@Service
@RequiredArgsConstructor
public class ProdutoService {

    private final ProdutoRepository produtoRepository;
    private final ProdutoMapper produtoMapper;

    /**
     * Lista todos los productos, ordenados por descripción.
     *
     * @return lista completa de productos
     */
    @Transactional(readOnly = true)
    public List<ProdutoResponse> listar() {
        return produtoRepository.findAllByOrderByDescripcionAsc().stream()
                .map(produtoMapper::toResponse)
                .toList();
    }

    /**
     * Lista los productos modificados desde la fecha indicada. Pensado para
     * sincronizaciones incrementales: la app pide solo los cambios desde la
     * última sincronización.
     *
     * @param modificadoDesde fecha de modificación mínima (inclusiva)
     * @return lista de productos modificados a partir de esa fecha
     */
    @Transactional(readOnly = true)
    public List<ProdutoResponse> listarModificadosDesde(LocalDateTime modificadoDesde) {
        return produtoRepository
                .findByFechaModificacionGreaterThanEqualOrderByDescripcionAsc(modificadoDesde)
                .stream()
                .map(produtoMapper::toResponse)
                .toList();
    }

    /**
     * Obtiene un producto por su identificador.
     *
     * @param id identificador del producto
     * @return el producto encontrado
     * @throws ResourceNotFoundException si no existe
     */
    @Transactional(readOnly = true)
    public ProdutoResponse obtenerPorId(Long id) {
        Produto produto = produtoRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Producto no encontrado: " + id));
        return produtoMapper.toResponse(produto);
    }
}
