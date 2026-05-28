package com.guzmanges.api.service;

import java.time.LocalDateTime;
import java.util.List;

import org.springframework.stereotype.Service;

import com.guzmanges.api.dto.ModoPagoResponse;
import com.guzmanges.api.entity.ModoPago;
import com.guzmanges.api.exception.ResourceNotFoundException;
import com.guzmanges.api.mapper.ModoPagoMapper;
import com.guzmanges.api.repository.ModoPagoRepository;

import lombok.RequiredArgsConstructor;

/**
 * Lógica de negocio de los modos de pago.
 * Es un catálogo de solo lectura, sincronizado desde Odoo.
 */
@Service
@RequiredArgsConstructor
public class ModoPagoService {

    private final ModoPagoRepository modoPagoRepository;
    private final ModoPagoMapper modoPagoMapper;

    /**
     * Lista los modos de pago activos, ordenados por descripción.
     *
     * @return lista de modos de pago
     */
    public List<ModoPagoResponse> listar() {
        return modoPagoRepository.findByActivoTrueOrderByDescripcionAsc().stream()
                .map(modoPagoMapper::toResponse)
                .toList();
    }

    /**
     * Lista los modos de pago (activos e inactivos) modificados desde la fecha indicada,
     * ordenados por descripción. Pensado para sincronizaciones incrementales.
     *
     * @param modificadoDesde fecha de modificación mínima (inclusiva)
     * @return lista de modos de pago modificados a partir de esa fecha
     */
    public List<ModoPagoResponse> listarModificadosDesde(LocalDateTime modificadoDesde) {
        return modoPagoRepository
                .findByFechaModificacionGreaterThanEqualOrderByDescripcionAsc(modificadoDesde)
                .stream()
                .map(modoPagoMapper::toResponse)
                .toList();
    }

    /**
     * Obtiene un modo de pago por su identificador.
     *
     * @param id identificador del modo de pago
     * @return el modo de pago encontrado
     * @throws ResourceNotFoundException si no existe
     */
    public ModoPagoResponse obtenerPorId(Long id) {
        ModoPago modoPago = modoPagoRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Modo de pago no encontrado: " + id));
        return modoPagoMapper.toResponse(modoPago);
    }
}
