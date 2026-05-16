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
@Table(name = "produto")
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

    @Column(columnDefinition = "TEXT")
    private String observaciones;

    private LocalDateTime fechaModificacion;
}
