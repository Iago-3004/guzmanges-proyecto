package com.guzmanges.api.repository;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.guzmanges.api.entity.TipoUsuario;
import com.guzmanges.api.entity.Usuario;

public interface UsuarioRepository extends JpaRepository<Usuario, Long> {

    Optional<Usuario> findByNombreUsuario(String nombreUsuario);

    Optional<Usuario> findByEmailIgnoreCase(String email);

    /**
     * Devuelve cualquier usuario con el rol indicado. La importación de
     * pedidos desde Odoo lo usa para resolver el campo {@code usuario_id}
     * (NOT NULL) de los pedidos cuyo vendedor en Odoo no tiene equivalente
     * local: como fallback se asigna al primer ADMIN, en vez de saltar el
     * pedido. Devuelve {@link Optional#empty()} si no existe ningún usuario
     * con ese rol (caso extremo: BD recién inicializada).
     */
    Optional<Usuario> findFirstByTipoUsuario(TipoUsuario tipoUsuario);
}
