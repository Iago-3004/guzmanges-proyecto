package com.guzmanges.api.exception;

import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import java.util.stream.Collectors;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

import tools.jackson.databind.exc.InvalidFormatException;

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
     * CIF duplicado al dar de alta un cliente: ya existe alguno con ese CIF.
     *
     * @param ex excepción con el mensaje y la lista de clientes existentes
     * @return HTTP 409 con el mensaje y la lista de coincidencias (para que la app las muestre)
     */
    @ExceptionHandler(CifDuplicadoException.class)
    public ResponseEntity<Map<String, Object>> handleCifDuplicado(CifDuplicadoException ex) {
        Map<String, Object> body = new HashMap<>();
        body.put("error", ex.getMessage());
        body.put("clientes", ex.getExistentes());
        return ResponseEntity.status(HttpStatus.CONFLICT).body(body);
    }

    /**
     * Alta o edición de usuario con un {@code nombreUsuario} o {@code email}
     * que ya pertenecen a otro usuario.
     *
     * @param ex excepción con el campo y el mensaje
     * @return HTTP 409 indicando qué campo provoca el conflicto
     */
    @ExceptionHandler(UsuarioDuplicadoException.class)
    public ResponseEntity<Map<String, String>> handleUsuarioDuplicado(UsuarioDuplicadoException ex) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(Map.of("campo", ex.getCampo(), "error", ex.getMessage()));
    }

    /**
     * El usuario no se puede eliminar (tiene dependencias, es el último ADMIN
     * o es el propio usuario autenticado). Devuelve los contadores de clientes
     * y pedidos asociados para que la pantalla de gestión pueda explicarlo.
     *
     * @param ex excepción con el mensaje y los contadores
     * @return HTTP 409 con el mensaje y el desglose de dependencias
     */
    @ExceptionHandler(UsuarioNoEliminableException.class)
    public ResponseEntity<Map<String, Object>> handleUsuarioNoEliminable(UsuarioNoEliminableException ex) {
        Map<String, Object> body = new HashMap<>();
        body.put("error", ex.getMessage());
        body.put("clientesAsociados", ex.getClientesAsociados());
        body.put("pedidosAsociados", ex.getPedidosAsociados());
        return ResponseEntity.status(HttpStatus.CONFLICT).body(body);
    }

    /**
     * Parámetro de la URL con tipo o formato incorrecto (p. ej. una fecha mal formada
     * en {@code ?modificadoDesde=texto-malo}, o un identificador no numérico).
     *
     * @param ex excepción con el detalle del parámetro y el valor recibido
     * @return HTTP 400 con un mensaje indicando qué parámetro es inválido
     */
    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public ResponseEntity<Map<String, String>> handleTypeMismatch(MethodArgumentTypeMismatchException ex) {
        String mensaje = "Parámetro '" + ex.getName() + "' con valor inválido: " + ex.getValue();
        return ResponseEntity.badRequest().body(Map.of("error", mensaje));
    }

    /**
     * El cuerpo JSON de la petición no se puede deserializar a la clase esperada.
     * Cubre, entre otros, el caso de un enum con un valor inválido (p. ej.
     * {@code "tipoUsuario": "FOO"}), un campo numérico con texto, o un JSON mal
     * formado. Cuando la causa raíz es un enum inválido, devuelve el campo y la
     * lista de valores aceptados para que el cliente pueda corregirlo.
     *
     * @param ex excepción de Spring al leer el cuerpo
     * @return HTTP 400 con un mensaje específico del error
     */
    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<Map<String, String>> handleNotReadable(HttpMessageNotReadableException ex) {
        Map<String, String> body = new HashMap<>();
        Throwable causa = ex.getCause();

        if (causa instanceof InvalidFormatException invalidFormat
                && invalidFormat.getTargetType() != null
                && invalidFormat.getTargetType().isEnum()) {
            String campo = invalidFormat.getPath().isEmpty()
                    ? "(desconocido)"
                    : invalidFormat.getPath().get(invalidFormat.getPath().size() - 1).getPropertyName();
            String valoresAceptados = Arrays.stream(invalidFormat.getTargetType().getEnumConstants())
                    .map(Object::toString)
                    .collect(Collectors.joining(", "));
            body.put("campo", campo);
            body.put("error", "Valor inválido '" + invalidFormat.getValue()
                    + "' para el campo '" + campo + "'. Valores aceptados: " + valoresAceptados);
        } else {
            body.put("error", "El cuerpo de la petición no es válido o está mal formado");
        }
        return ResponseEntity.badRequest().body(body);
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
