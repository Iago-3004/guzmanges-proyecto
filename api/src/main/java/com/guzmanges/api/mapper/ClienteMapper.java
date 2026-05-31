package com.guzmanges.api.mapper;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.guzmanges.api.dto.ClienteResponse;
import com.guzmanges.api.entity.Cliente;

/**
 * Conversión de la entidad Cliente a su DTO de respuesta.
 * Reutiliza los mappers de los catálogos para anidar el modo y la condición de pago.
 */
@Component
public class ClienteMapper {

    private final ModoPagoMapper modoPagoMapper;
    private final CondicionPagoMapper condicionPagoMapper;

    /**
     * Palabra clave que se busca dentro del nombre de la posición fiscal para
     * decidir si el cliente está sujeto al recargo de equivalencia. Se configura
     * con la propiedad {@code app.posicion-fiscal.recargo-keyword}; por defecto
     * "recargo". Si Odoo usa otro término (p. ej. "REQ"), basta con cambiar la
     * propiedad sin tocar el código.
     */
    private final String recargoKeyword;

    public ClienteMapper(ModoPagoMapper modoPagoMapper,
                         CondicionPagoMapper condicionPagoMapper,
                         @Value("${app.posicion-fiscal.recargo-keyword:recargo}") String recargoKeyword) {
        this.modoPagoMapper = modoPagoMapper;
        this.condicionPagoMapper = condicionPagoMapper;
        this.recargoKeyword = recargoKeyword.toLowerCase();
    }

    public ClienteResponse toResponse(Cliente cliente) {
        return new ClienteResponse(
                cliente.getId(),
                cliente.getIdOdoo(),
                cliente.getNombreComercial(),
                cliente.getRazonSocial(),
                cliente.getCif(),
                cliente.getDireccion(),
                cliente.getLocalidad(),
                cliente.getCodigoPostal(),
                cliente.getProvincia(),
                cliente.getTelefono(),
                cliente.getMovil(),
                cliente.getEmail(),
                cliente.getPosicionFiscal(),
                tieneRecargoEquivalencia(cliente.getPosicionFiscal()),
                cliente.getModoPago() != null ? modoPagoMapper.toResponse(cliente.getModoPago()) : null,
                cliente.getCondicionPago() != null ? condicionPagoMapper.toResponse(cliente.getCondicionPago()) : null,
                cliente.getComercial() != null ? cliente.getComercial().getNombreUsuario() : null,
                cliente.getActivo(),
                cliente.getEstadoSync()
        );
    }

    /**
     * Decide si el cliente está sujeto al recargo de equivalencia a partir del
     * nombre de su posición fiscal: lo está si el nombre (ignorando
     * mayúsculas/minúsculas) contiene la palabra clave configurada en
     * {@link #recargoKeyword}.
     *
     * @param posicionFiscal nombre de la posición fiscal del cliente
     * @return true si está en régimen de recargo de equivalencia
     */
    private boolean tieneRecargoEquivalencia(String posicionFiscal) {
        return posicionFiscal != null
                && posicionFiscal.toLowerCase().contains(recargoKeyword);
    }
}
