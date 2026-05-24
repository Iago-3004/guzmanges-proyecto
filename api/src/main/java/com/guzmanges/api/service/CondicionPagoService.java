package com.guzmanges.api.service;

import java.util.List;

import org.springframework.stereotype.Service;

import com.guzmanges.api.dto.CondicionPagoResponse;
import com.guzmanges.api.entity.CondicionPago;
import com.guzmanges.api.exception.ResourceNotFoundException;
import com.guzmanges.api.mapper.CondicionPagoMapper;
import com.guzmanges.api.repository.CondicionPagoRepository;

import lombok.RequiredArgsConstructor;

/**
 * Lógica de negocio de las condiciones de pago.
 * Es un catálogo de solo lectura, sincronizado desde Odoo.
 */
@Service
@RequiredArgsConstructor
public class CondicionPagoService {

    private final CondicionPagoRepository condicionPagoRepository;
    private final CondicionPagoMapper condicionPagoMapper;

    /**
     * Lista las condiciones de pago activas, ordenadas por descripción.
     *
     * @return lista de condiciones de pago
     */
    public List<CondicionPagoResponse> listar() {
        return condicionPagoRepository.findByActivoTrueOrderByDescripcionAsc().stream()
                .map(condicionPagoMapper::toResponse)
                .toList();
    }

    /**
     * Obtiene una condición de pago por su identificador.
     *
     * @param id identificador de la condición de pago
     * @return la condición de pago encontrada
     * @throws ResourceNotFoundException si no existe
     */
    public CondicionPagoResponse obtenerPorId(Long id) {
        CondicionPago condicionPago = condicionPagoRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Condición de pago no encontrada: " + id));
        return condicionPagoMapper.toResponse(condicionPago);
    }
}
