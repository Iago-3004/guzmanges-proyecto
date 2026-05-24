package com.guzmanges.api.exception;

import java.util.HashMap;
import java.util.Map;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.resource.NoResourceFoundException;

import lombok.extern.slf4j.Slf4j;

/**
 * Manejador global de excepciones de la API.
 *
 * Centraliza la traducción de excepciones a respuestas HTTP con un cuerpo JSON
 * coherente, evitando que cada controlador tenga que gestionar los errores.
 */
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {

    /**
     * Credenciales de login incorrectas.
     *
     * @param ex excepción lanzada por el AuthenticationManager
     * @return HTTP 401 con un mensaje de error
     */
    @ExceptionHandler(BadCredentialsException.class)
    public ResponseEntity<Map<String, String>> handleBadCredentials(BadCredentialsException ex) {
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(Map.of("error", "Credenciales incorrectas"));
    }

    /**
     * Errores de validación de los datos de entrada (Bean Validation).
     *
     * @param ex excepción con los campos que han fallado la validación
     * @return HTTP 400 con un mapa campo → mensaje de error
     */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, String>> handleValidation(MethodArgumentNotValidException ex) {
        Map<String, String> errores = new HashMap<>();
        ex.getBindingResult().getFieldErrors().forEach(error ->
                errores.put(error.getField(), error.getDefaultMessage()));
        return ResponseEntity.badRequest().body(errores);
    }

    /**
     * Recurso no encontrado.
     *
     * @param ex excepción con el detalle del recurso no encontrado
     * @return HTTP 404 con un mensaje de error
     */
    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<Map<String, String>> handleNotFound(ResourceNotFoundException ex) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(Map.of("error", ex.getMessage()));
    }

    /**
     * Ruta o recurso inexistente (incluye rutas mal escritas, p. ej. con barra final).
     * Se devuelve 404 sin volcar la traza, ya que es un error del cliente, no del servidor.
     *
     * @param ex excepción de recurso no encontrado
     * @return HTTP 404 con un mensaje de error
     */
    @ExceptionHandler(NoResourceFoundException.class)
    public ResponseEntity<Map<String, String>> handleNoResource(NoResourceFoundException ex) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(Map.of("error", "Ruta no encontrada"));
    }

    /**
     * Cualquier otra excepción no controlada explícitamente.
     *
     * @param ex excepción inesperada
     * @return HTTP 500 con un mensaje genérico (el detalle se registra en el log)
     */
    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, String>> handleGeneric(Exception ex) {
        log.error("Error no controlado", ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Error interno del servidor"));
    }
}
