package com.guzmanges.api.service;

import java.util.List;

import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.guzmanges.api.dto.ActualizarUsuarioRequest;
import com.guzmanges.api.dto.CambiarContrasenaRequest;
import com.guzmanges.api.dto.CrearUsuarioRequest;
import com.guzmanges.api.dto.UsuarioResponse;
import com.guzmanges.api.entity.TipoUsuario;
import com.guzmanges.api.entity.Usuario;
import com.guzmanges.api.exception.ResourceNotFoundException;
import com.guzmanges.api.exception.UsuarioDuplicadoException;
import com.guzmanges.api.exception.UsuarioNoEliminableException;
import com.guzmanges.api.mapper.UsuarioMapper;
import com.guzmanges.api.repository.ClienteRepository;
import com.guzmanges.api.repository.PedidoRepository;
import com.guzmanges.api.repository.UsuarioRepository;

import lombok.RequiredArgsConstructor;

/**
 * Lógica de negocio de la gestión de usuarios. Solo accesible desde el
 * controlador para usuarios ADMIN; el filtro de rol lo aplica Spring
 * Security a nivel de ruta.
 *
 * Reglas de negocio:
 * <ul>
 *   <li>{@code nombreUsuario} y {@code email} son únicos (insensible a
 *       mayúsculas).</li>
 *   <li>El {@code nombreUsuario} no se puede modificar tras el alta, ya
 *       que es la clave por la que se autentica el usuario y se referencia
 *       en logs y dependencias.</li>
 *   <li>La contraseña se actualiza por un endpoint específico para no
 *       mezclarla con el resto de datos.</li>
 *   <li>Un usuario con clientes o pedidos asociados no se puede eliminar.</li>
 *   <li>El último ADMIN no se puede eliminar ni degradar a PREVENTA, para
 *       que el sistema no quede sin acceso administrativo.</li>
 *   <li>Un ADMIN no puede borrarse a sí mismo (la sesión activa quedaría
 *       en un estado inconsistente).</li>
 * </ul>
 */
@Service
@RequiredArgsConstructor
public class UsuarioService {

    private final UsuarioRepository usuarioRepository;
    private final ClienteRepository clienteRepository;
    private final PedidoRepository pedidoRepository;
    private final UsuarioMapper usuarioMapper;
    private final PasswordEncoder passwordEncoder;

    /**
     * Lista todos los usuarios, ordenados por nombre.
     *
     * @return lista de usuarios
     */
    @Transactional(readOnly = true)
    public List<UsuarioResponse> listar() {
        return usuarioRepository.findAllByOrderByNombreAsc().stream()
                .map(usuarioMapper::toResponse)
                .toList();
    }

    /**
     * Obtiene un usuario por su identificador.
     *
     * @param id identificador del usuario
     * @return el usuario
     * @throws ResourceNotFoundException si no existe
     */
    @Transactional(readOnly = true)
    public UsuarioResponse obtenerPorId(Long id) {
        Usuario usuario = buscar(id);
        return usuarioMapper.toResponse(usuario);
    }

    /**
     * Da de alta un nuevo usuario. Cifra la contraseña con BCrypt antes de
     * persistirla.
     *
     * @param request datos del nuevo usuario
     * @return el usuario creado, sin contraseña
     * @throws UsuarioDuplicadoException si {@code nombreUsuario} o {@code email}
     *                                   ya están en uso
     */
    @Transactional
    public UsuarioResponse crear(CrearUsuarioRequest request) {
        if (usuarioRepository.existsByNombreUsuarioIgnoreCase(request.nombreUsuario())) {
            throw new UsuarioDuplicadoException(
                    "nombreUsuario",
                    "Ya existe un usuario con el nombre '" + request.nombreUsuario() + "'");
        }
        if (usuarioRepository.existsByEmailIgnoreCase(request.email())) {
            throw new UsuarioDuplicadoException(
                    "email",
                    "Ya existe un usuario con el email '" + request.email() + "'");
        }

        Usuario usuario = Usuario.builder()
                .nombre(request.nombre().trim())
                .nombreUsuario(request.nombreUsuario().trim())
                .email(request.email().trim())
                .contrasena(passwordEncoder.encode(request.contrasena()))
                .tipoUsuario(request.tipoUsuario())
                .build();

        return usuarioMapper.toResponse(usuarioRepository.save(usuario));
    }

    /**
     * Edita un usuario existente. No permite cambiar {@code nombreUsuario}
     * ni {@code contrasena} (van por sus propios flujos).
     *
     * Si la edición intentase degradar al último ADMIN, se bloquea con un
     * 409 explicando que dejaría el sistema sin administración.
     *
     * @param id      identificador del usuario
     * @param request nuevos datos
     * @return el usuario actualizado
     */
    @Transactional
    public UsuarioResponse actualizar(Long id, ActualizarUsuarioRequest request) {
        Usuario usuario = buscar(id);

        if (!usuario.getEmail().equalsIgnoreCase(request.email())
                && usuarioRepository.existsByEmailIgnoreCase(request.email())) {
            throw new UsuarioDuplicadoException(
                    "email",
                    "Ya existe un usuario con el email '" + request.email() + "'");
        }

        boolean degradandoUltimoAdmin = usuario.getTipoUsuario() == TipoUsuario.ADMIN
                && request.tipoUsuario() != TipoUsuario.ADMIN
                && usuarioRepository.countByTipoUsuario(TipoUsuario.ADMIN) <= 1;
        if (degradandoUltimoAdmin) {
            throw new UsuarioNoEliminableException(
                    "No se puede degradar al último ADMIN: dejaría el sistema sin acceso administrativo",
                    0, 0);
        }

        usuario.setNombre(request.nombre().trim());
        usuario.setEmail(request.email().trim());
        usuario.setTipoUsuario(request.tipoUsuario());

        return usuarioMapper.toResponse(usuarioRepository.save(usuario));
    }

    /**
     * Cambia la contraseña de un usuario. Cifra la nueva con BCrypt antes
     * de persistirla.
     *
     * @param id      identificador del usuario
     * @param request contiene la nueva contraseña
     */
    @Transactional
    public void cambiarContrasena(Long id, CambiarContrasenaRequest request) {
        Usuario usuario = buscar(id);
        usuario.setContrasena(passwordEncoder.encode(request.contrasena()));
        usuarioRepository.save(usuario);
    }

    /**
     * Elimina un usuario. Solo posible si no tiene clientes ni pedidos
     * asociados, no es el último ADMIN, y no es el propio usuario
     * autenticado.
     *
     * @param id                identificador del usuario a eliminar
     * @param usernameAutenticado nombre de usuario que está realizando la operación
     * @throws ResourceNotFoundException     si no existe
     * @throws UsuarioNoEliminableException si tiene dependencias, es el último ADMIN
     *                                       o es el propio autenticado
     */
    @Transactional
    public void eliminar(Long id, String usernameAutenticado) {
        Usuario usuario = buscar(id);

        if (usuario.getNombreUsuario().equals(usernameAutenticado)) {
            throw new UsuarioNoEliminableException(
                    "No puedes eliminar tu propio usuario mientras estás autenticado con él",
                    0, 0);
        }

        long clientes = clienteRepository.countByComercialId(id);
        long pedidos = pedidoRepository.countByUsuarioId(id);
        if (clientes > 0 || pedidos > 0) {
            throw new UsuarioNoEliminableException(
                    "El usuario tiene " + clientes + " cliente(s) y " + pedidos
                            + " pedido(s) asociados. Reasígnalos o elimínalos antes de borrar el usuario.",
                    clientes, pedidos);
        }

        if (usuario.getTipoUsuario() == TipoUsuario.ADMIN
                && usuarioRepository.countByTipoUsuario(TipoUsuario.ADMIN) <= 1) {
            throw new UsuarioNoEliminableException(
                    "No se puede eliminar al último ADMIN: dejaría el sistema sin acceso administrativo",
                    0, 0);
        }

        usuarioRepository.delete(usuario);
    }

    private Usuario buscar(Long id) {
        return usuarioRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Usuario no encontrado: " + id));
    }
}
