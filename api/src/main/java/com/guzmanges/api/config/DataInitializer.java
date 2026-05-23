package com.guzmanges.api.config;

import org.springframework.boot.CommandLineRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

import com.guzmanges.api.entity.TipoUsuario;
import com.guzmanges.api.entity.Usuario;
import com.guzmanges.api.repository.UsuarioRepository;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

/**
 * Inicializa datos seed en la BD al arrancar la aplicación.
 *
 * Inserta 2 usuarios iniciales (admin y preventa) solo si la tabla de
 * usuarios está vacía. Idempotente: en las ejecuciones posteriores
 * no duplica datos.
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class DataInitializer implements CommandLineRunner {

    private final UsuarioRepository usuarioRepository;
    private final PasswordEncoder passwordEncoder;

    @Override
    public void run(String... args) {
        if (usuarioRepository.count() > 0) {
            log.info("BD ya contiene usuarios — saltando inicialización de datos iniciales.");
            return;
        }

        Usuario admin = Usuario.builder()
                .nombre("Administrador")
                .nombreUsuario("admin")
                .email("admin@guzmanges.local")
                .contrasena(passwordEncoder.encode("admin"))
                .tipoUsuario(TipoUsuario.ADMIN)
                .build();

        Usuario preventa = Usuario.builder()
                .nombre("Comercial Preventa")
                .nombreUsuario("preventa")
                .email("preventa@guzmanges.local")
                .contrasena(passwordEncoder.encode("preventa"))
                .tipoUsuario(TipoUsuario.PREVENTA)
                .build();

        usuarioRepository.save(admin);
        usuarioRepository.save(preventa);

        log.info("Usuarios iniciales creados: admin (ADMIN) y preventa (PREVENTA).");
    }
}
