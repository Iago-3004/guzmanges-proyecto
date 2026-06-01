package com.guzmanges.api.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.guzmanges.api.dto.JwtResponse;
import com.guzmanges.api.dto.LoginRequest;
import com.guzmanges.api.service.AuthService;

import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;

/**
 * Controlador REST de autenticación.
 *
 * Expone el endpoint público de login. Es uno de los pocos endpoints que no
 * requiere token JWT (configurado en {@code SecurityConfig} bajo {@code /auth/**}).
 */
@RestController
@RequestMapping("/auth")
@RequiredArgsConstructor
@Tag(name = "Autenticación", description = "Login de usuarios. Único bloque sin JWT obligatorio.")
public class AuthController {

    private final AuthService authService;

    /**
     * Autentica al usuario y devuelve un token JWT si las credenciales son válidas.
     *
     * @param request credenciales de acceso, validadas con Bean Validation
     * @return HTTP 200 con el token y los datos de sesión; HTTP 401 si las
     *         credenciales son incorrectas; HTTP 400 si faltan campos obligatorios
     */
    @PostMapping("/login")
    public ResponseEntity<JwtResponse> login(@Valid @RequestBody LoginRequest request) {
        return ResponseEntity.ok(authService.login(request));
    }
}
