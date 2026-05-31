package com.guzmanges.api.entity;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Entity
@Table(name = "produtos")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Produto {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(unique = true, length = 50)
    private String idOdoo;

    @Column(length = 50)
    private String referencia;

    @Column(length = 50)
    private String codigoBarras;

    @Column(nullable = false, length = 255)
    private String descripcion;

    @Column(length = 50)
    private String tipoProduto;

    private Integer stock;

    @Column(precision = 10, scale = 2)
    private BigDecimal precioVenta;

    /**
     * IVA por defecto del producto, en porcentaje (p. ej. 21.00 para el 21 %).
     * Es el impuesto que arrastra el producto en Odoo (taxes_id).
     *
     * En las líneas de pedido la app autocompleta el IVA con este valor; el
     * cálculo definitivo lo recalcula Odoo al confirmar, aplicando además la
     * posición fiscal del cliente (puede mapear el IVA del producto a otro
     * tipo o exentarlo en operaciones intracomunitarias).
     */
    @Column(precision = 5, scale = 2)
    private BigDecimal iva;

    @Column(columnDefinition = "TEXT")
    private String observaciones;

    private LocalDateTime fechaModificacion;
}
