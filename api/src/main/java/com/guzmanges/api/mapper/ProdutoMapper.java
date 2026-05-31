package com.guzmanges.api.mapper;

import org.springframework.stereotype.Component;

import com.guzmanges.api.dto.ProdutoResponse;
import com.guzmanges.api.entity.Produto;

/**
 * Conversión de la entidad {@link Produto} a su DTO de respuesta.
 */
@Component
public class ProdutoMapper {

    /**
     * Construye un {@link ProdutoResponse} a partir de un producto.
     *
     * @param produto entidad a convertir
     * @return DTO equivalente
     */
    public ProdutoResponse toResponse(Produto produto) {
        return new ProdutoResponse(
                produto.getId(),
                produto.getIdOdoo(),
                produto.getReferencia(),
                produto.getCodigoBarras(),
                produto.getDescripcion(),
                produto.getTipoProduto(),
                produto.getStock(),
                produto.getPrecioVenta(),
                produto.getIva(),
                produto.getObservaciones(),
                produto.getFechaModificacion()
        );
    }
}
