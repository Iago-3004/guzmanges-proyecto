package com.guzmanges.api.entity;

import java.time.LocalDateTime;

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
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Entity
@Table(name = "clientes")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Cliente {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(unique = true, length = 50)
    private String idOdoo;

    @Column(nullable = false, length = 150)
    private String nombreComercial;

    @Column(length = 150)
    private String razonSocial;

    @Column(length = 20)
    private String cif;

    @Column(length = 200)
    private String direccion;

    @Column(length = 100)
    private String localidad;

    @Column(length = 10)
    private String codigoPostal;

    @Column(length = 50)
    private String provincia;

    @Column(length = 20)
    private String telefono;

    @Column(length = 20)
    private String movil;

    @Column(length = 150)
    private String email;

    @Column(length = 50)
    private String posicionFiscal;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "modo_pago_id")
    private ModoPago modoPago;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "condicion_pago_id")
    private CondicionPago condicionPago;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "comercial_id")
    private Usuario comercial;

    private LocalDateTime fechaModificacion;

    @Column(nullable = false)
    private Boolean activo;

    @Enumerated(EnumType.STRING)
    @Column(length = 20)
    private EstadoSync estadoSync;
}
