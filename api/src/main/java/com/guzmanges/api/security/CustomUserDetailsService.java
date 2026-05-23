package com.guzmanges.api.security;

import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

import com.guzmanges.api.entity.Usuario;
import com.guzmanges.api.repository.UsuarioRepository;

import lombok.RequiredArgsConstructor;

/**
 * Servicio que adapta la entidad {@link Usuario} de la base de datos al
 * contrato {@link UserDetailsService} requerido por Spring Security.
 *
 * Spring Security invoca este servicio durante el proceso de autenticación
 * para cargar los datos del usuario a partir de su nombre de usuario. Una vez
 * cargado, Spring compara la contraseña proporcionada con la almacenada
 * (cifrada con BCrypt) usando el {@code PasswordEncoder} configurado.
 *
 * El rol del usuario ({@code ADMIN} o {@code PREVENTA}) se traduce a la
 * autoridad de Spring Security {@code ROLE_ADMIN} o {@code ROLE_PREVENTA}.
 * El prefijo {@code ROLE_} lo añade automáticamente {@code User.builder().roles()}.
 */
@Service
@RequiredArgsConstructor
public class CustomUserDetailsService implements UserDetailsService {

    private final UsuarioRepository usuarioRepository;

    /**
     * Carga un usuario por su nombre de usuario para que Spring Security
     * pueda autenticarlo.
     *
     * @param nombreUsuario nombre de usuario único proporcionado en la petición de login
     * @return los detalles del usuario en el formato de Spring Security, con
     *         su contraseña cifrada y su autoridad correspondiente al rol
     * @throws UsernameNotFoundException si no existe ningún usuario con ese nombre
     */
    @Override
    public UserDetails loadUserByUsername(String nombreUsuario) throws UsernameNotFoundException {
        Usuario usuario = usuarioRepository.findByNombreUsuario(nombreUsuario)
                .orElseThrow(() -> new UsernameNotFoundException(
                        "Usuario no encontrado: " + nombreUsuario));

        return User.builder()
                .username(usuario.getNombreUsuario())
                .password(usuario.getContrasena())
                .roles(usuario.getTipoUsuario().name())
                .build();
    }
}
