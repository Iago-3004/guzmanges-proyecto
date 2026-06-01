package com.guzmanges.api.entity;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Entity
@Table(name = "pedidos")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Pedido {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(unique = true, length = 50)
    private String idOdoo;

    @Column(length = 50)
    private String numero;

    private LocalDateTime fecha;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private EstadoPedido estadoPedido;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private EstadoSync estadoSync;

    @Column(precision = 10, scale = 2)
    private BigDecimal totalBase;

    @Column(precision = 10, scale = 2)
    private BigDecimal totalIva;

    @Column(precision = 10, scale = 2)
    private BigDecimal totalRE;

    @Column(precision = 10, scale = 2)
    private BigDecimal total;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "cliente_id", nullable = false)
    private Cliente cliente;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "usuario_id", nullable = false)
    private Usuario usuario;

    @OneToMany(mappedBy = "pedido", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.LAZY)
    @Builder.Default
    private List<LineaPedido> lineas = new ArrayList<>();

    private LocalDateTime fechaModificacion;

    /**
     * Marca temporal {@code write_date} del registro en Odoo. Permite saber
     * si un pedido ya importado ha cambiado allí desde la última vez (cambio
     * de estado, anulación, etc.) sin tener que recalcular el resto de campos
     * cada vez. Null para los pedidos creados desde la app antes de subirse.
     */
    private LocalDateTime fechaModificacionOdoo;
}
