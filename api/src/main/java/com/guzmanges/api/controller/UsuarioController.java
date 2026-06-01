package com.guzmanges.api.controller;

import java.util.List;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.guzmanges.api.dto.ActualizarUsuarioRequest;
import com.guzmanges.api.dto.CambiarContrasenaRequest;
import com.guzmanges.api.dto.CrearUsuarioRequest;
import com.guzmanges.api.dto.UsuarioResponse;
import com.guzmanges.api.service.UsuarioService;

import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;

/**
 * Controlador REST de gestión de usuarios. Requiere autenticación JWT con
 * rol ADMIN (la restricción se aplica en {@code SecurityConfig}).
 *
 * Cubre el alta, la consulta, la edición, el cambio de contraseña y el
 * borrado de usuarios. La app móvil no usa estos endpoints: la gestión
 * de usuarios es responsabilidad del administrador desde el backend.
 */
@RestController
@RequestMapping("/usuarios")
@RequiredArgsConstructor
@Tag(name = "Usuarios", description = "Gestión de usuarios (solo ADMIN). No se usa desde la app móvil.")
public class UsuarioController {

    private final UsuarioService usuarioService;

    /**
     * Lista todos los usuarios, ordenados por nombre.
     *
     * @return lista de usuarios
     */
    @GetMapping
    public List<UsuarioResponse> listar() {
        return usuarioService.listar();
    }

    /**
     * Devuelve un usuario por su identificador.
     *
     * @param id identificador del usuario
     * @return el usuario; HTTP 404 si no existe
     */
    @GetMapping("/{id}")
    public UsuarioResponse obtener(@PathVariable Long id) {
        return usuarioService.obtenerPorId(id);
    }

    /**
     * Da de alta un nuevo usuario.
     *
     * @param request datos del nuevo usuario
     * @return HTTP 201 con el usuario creado; HTTP 400 si los datos no son válidos;
     *         HTTP 409 si {@code nombreUsuario} o {@code email} ya existen
     */
    @PostMapping
    public ResponseEntity<UsuarioResponse> crear(@Valid @RequestBody CrearUsuarioRequest request) {
        UsuarioResponse creado = usuarioService.crear(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(creado);
    }

    /**
     * Edita un usuario existente. No permite cambiar {@code nombreUsuario}
     * ni {@code contrasena} (van por sus propios flujos).
     *
     * @param id      identificador del usuario
     * @param request nuevos datos
     * @return el usuario actualizado; HTTP 404 si no existe; HTTP 409 si el
     *         email ya pertenece a otro usuario o se intenta degradar al último ADMIN
     */
    @PutMapping("/{id}")
    public UsuarioResponse actualizar(@PathVariable Long id,
                                      @Valid @RequestBody ActualizarUsuarioRequest request) {
        return usuarioService.actualizar(id, request);
    }

    /**
     * Cambia la contraseña de un usuario.
     *
     * @param id      identificador del usuario
     * @param request nueva contraseña
     * @return HTTP 204 si se actualiza correctamente; HTTP 404 si no existe;
     *         HTTP 400 si la contraseña no cumple la longitud mínima
     */
    @PatchMapping("/{id}/contrasena")
    public ResponseEntity<Void> cambiarContrasena(@PathVariable Long id,
                                                  @Valid @RequestBody CambiarContrasenaRequest request) {
        usuarioService.cambiarContrasena(id, request);
        return ResponseEntity.noContent().build();
    }

    /**
     * Elimina un usuario. Bloquea la operación si tiene clientes o pedidos
     * asociados, si es el último ADMIN, o si es el propio usuario autenticado.
     *
     * @param id             identificador del usuario
     * @param authentication contexto de seguridad (para detectar autoeliminación)
     * @return HTTP 204 si se elimina; HTTP 404 si no existe; HTTP 409 con
     *         detalle de dependencias si no se puede eliminar
     */
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> eliminar(@PathVariable Long id, Authentication authentication) {
        usuarioService.eliminar(id, authentication.getName());
        return ResponseEntity.noContent().build();
    }
}
