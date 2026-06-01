package com.guzmanges.api.odoo.service;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.guzmanges.api.entity.Cliente;
import com.guzmanges.api.entity.CondicionPago;
import com.guzmanges.api.entity.EstadoSync;
import com.guzmanges.api.entity.ModoPago;
import com.guzmanges.api.entity.Usuario;
import com.guzmanges.api.odoo.mapper.OdooClienteMapper;
import com.guzmanges.api.odoo.repository.OdooClienteRepository;
import com.guzmanges.api.repository.ClienteRepository;
import com.guzmanges.api.repository.CondicionPagoRepository;
import com.guzmanges.api.repository.ModoPagoRepository;
import com.guzmanges.api.repository.PedidoRepository;
import com.guzmanges.api.repository.UsuarioRepository;

import lombok.RequiredArgsConstructor;

/**
 * Servicio de sincronización de clientes con Odoo.
 *
 * En este paso implementa la importación (Odoo → MySQL): refleja en la BD local los clientes
 * existentes en Odoo. El envío de las altas locales (MySQL → Odoo) se añade en el paso siguiente.
 */
@Service
@RequiredArgsConstructor
public class OdooSyncService {

    private static final Logger log = LoggerFactory.getLogger(OdooSyncService.class);

    private final ClienteRepository clienteRepository;
    private final CondicionPagoRepository condicionPagoRepository;
    private final ModoPagoRepository modoPagoRepository;
    private final UsuarioRepository usuarioRepository;
    private final PedidoRepository pedidoRepository;
    private final OdooClienteRepository odooClienteRepository;
    private final OdooClienteMapper odooClienteMapper;

    /**
     * Importa los clientes de Odoo a la BD local.
     * Para cada cliente de Odoo: si ya existe en local (por idOdoo) actualiza sus datos,
     * y si no existe lo crea. Los clientes locales sin idOdoo (altas pendientes de enviar)
     * no se ven afectados.
     *
     * @return número de clientes importados o actualizados
     */
    @Transactional
    public int importarClientesDesdeOdoo() {
        log.info("=== IMPORTANDO CLIENTES DESDE ODOO ===");
        List<Map<String, Object>> clientesOdoo = odooClienteRepository.findClientes();
        log.info("Clientes encontrados en Odoo: {}", clientesOdoo.size());

        int nuevos = 0;
        int actualizados = 0;
        int sinCambios = 0;
        // Cache vendedor de Odoo (user_id) -> Usuario local, para no consultar res.users repetidamente
        Map<Integer, Usuario> cacheComercial = new HashMap<>();
        // Ids de Odoo vistos en esta importación, para detectar después los clientes borrados
        Set<String> idsVistos = new HashSet<>();
        for (Map<String, Object> datosOdoo : clientesOdoo) {
            try {
                String idOdoo = String.valueOf(((Number) datosOdoo.get("id")).longValue());
                idsVistos.add(idOdoo);
                Cliente desdeOdoo = odooClienteMapper.fromOdooToCliente(
                        datosOdoo, this::buscarCondicionPago, this::buscarModoPago,
                        odooUserId -> resolverComercial(odooUserId, cacheComercial));

                Optional<Cliente> existente = clienteRepository.findByIdOdoo(idOdoo);
                if (existente.isPresent()) {
                    Cliente cliente = existente.get();
                    // Solo se actualiza si en Odoo se modificó después de la última importación
                    if (cliente.getFechaModificacionOdoo() != null
                            && desdeOdoo.getFechaModificacionOdoo() != null
                            && !desdeOdoo.getFechaModificacionOdoo().isAfter(cliente.getFechaModificacionOdoo())) {
                        sinCambios++;
                        continue;
                    }
                    copiarDatosDeOdoo(cliente, desdeOdoo);
                    clienteRepository.save(cliente);
                    actualizados++;
                } else {
                    clienteRepository.save(desdeOdoo);
                    nuevos++;
                    log.info("[ODOO -> DB] Nuevo cliente: {} (idOdoo: {})", desdeOdoo.getRazonSocial(), idOdoo);
                }
            } catch (Exception e) {
                log.error("[ODOO -> DB] Error importando cliente idOdoo={}: {}", datosOdoo.get("id"), e.getMessage());
            }
        }

        log.info("=== CLIENTES: {} nuevos, {} actualizados, {} sin cambios (de {} en Odoo) ===",
                nuevos, actualizados, sinCambios, clientesOdoo.size());

        reconciliarClientesBorrados(idsVistos);
        return nuevos + actualizados;
    }

    /**
     * Detecta y procesa los clientes borrados por completo en Odoo. Un cliente local con idOdoo
     * cuyo id no figura entre los vistos en la importación es un candidato; se confirma consultando
     * a Odoo si ese id todavía existe (activo o archivado), para no confundir un borrado real con un
     * cliente filtrado por empresa o que dejó de ser cliente. Los confirmados como borrados se
     * eliminan de MySQL, salvo que tengan pedidos asociados: en ese caso se desactivan (activo=false)
     * para no perder el historial ni romper la integridad referencial.
     *
     * @param idsVistos ids de Odoo (como String) de los clientes que sí existen en Odoo
     */
    private void reconciliarClientesBorrados(Set<String> idsVistos) {
        List<Cliente> candidatos = clienteRepository.findByIdOdooIsNotNull().stream()
                .filter(cliente -> !idsVistos.contains(cliente.getIdOdoo()))
                .toList();
        if (candidatos.isEmpty()) {
            return;
        }

        // Confirmar en Odoo cuáles de los candidatos siguen existiendo (activos o archivados)
        List<Integer> idsCandidatos = candidatos.stream()
                .map(cliente -> Integer.parseInt(cliente.getIdOdoo()))
                .toList();
        Set<Integer> existentes = odooClienteRepository.findExistingIds(idsCandidatos);

        int borrados = 0;
        int desactivados = 0;
        for (Cliente cliente : candidatos) {
            if (existentes.contains(Integer.parseInt(cliente.getIdOdoo()))) {
                continue; // Sigue existiendo en Odoo (filtrado por empresa/customer_rank): no se toca
            }
            if (pedidoRepository.existsByClienteId(cliente.getId())) {
                cliente.setActivo(false);
                clienteRepository.save(cliente);
                desactivados++;
                log.warn("[ODOO -> DB] Cliente '{}' (idOdoo {}) borrado en Odoo pero tiene pedidos: "
                        + "se desactiva en vez de borrarse", cliente.getRazonSocial(), cliente.getIdOdoo());
            } else {
                clienteRepository.delete(cliente);
                borrados++;
                log.info("[ODOO -> DB] Cliente '{}' (idOdoo {}) borrado en Odoo: eliminado de MySQL",
                        cliente.getRazonSocial(), cliente.getIdOdoo());
            }
        }

        if (borrados > 0 || desactivados > 0) {
            log.info("=== RECONCILIACIÓN DE BORRADOS: {} eliminados, {} desactivados (con pedidos) ===",
                    borrados, desactivados);
        }
    }

    private CondicionPago buscarCondicionPago(String idOdoo) {
        return condicionPagoRepository.findByIdOdoo(idOdoo).orElse(null);
    }

    private ModoPago buscarModoPago(String idOdoo) {
        return modoPagoRepository.findByIdOdoo(idOdoo).orElse(null);
    }

    /**
     * Copia en el cliente local los datos provenientes de Odoo. No toca el comercial
     * (asignación local) ni el idOdoo (que ya está establecido).
     */
    private void copiarDatosDeOdoo(Cliente destino, Cliente desdeOdoo) {
        destino.setRazonSocial(desdeOdoo.getRazonSocial());
        destino.setCif(desdeOdoo.getCif());
        destino.setNombreComercial(desdeOdoo.getNombreComercial());
        destino.setDireccion(desdeOdoo.getDireccion());
        destino.setLocalidad(desdeOdoo.getLocalidad());
        destino.setCodigoPostal(desdeOdoo.getCodigoPostal());
        destino.setProvincia(desdeOdoo.getProvincia());
        destino.setTelefono(desdeOdoo.getTelefono());
        destino.setMovil(desdeOdoo.getMovil());
        destino.setEmail(desdeOdoo.getEmail());
        destino.setPosicionFiscal(desdeOdoo.getPosicionFiscal());
        destino.setCondicionPago(desdeOdoo.getCondicionPago());
        destino.setModoPago(desdeOdoo.getModoPago());
        destino.setComercial(desdeOdoo.getComercial());
        destino.setActivo(desdeOdoo.getActivo());
        destino.setEstadoSync(EstadoSync.SINCRONIZADO);
        destino.setFechaModificacion(LocalDateTime.now());
        destino.setFechaModificacionOdoo(desdeOdoo.getFechaModificacionOdoo());
    }

    /**
     * Resuelve el comercial local a partir del id del vendedor (user_id) de Odoo:
     * obtiene su login/email en Odoo y busca el Usuario local con ese email.
     * Devuelve null si Odoo no tiene vendedor o si no hay un Usuario local con ese email.
     * Usa una cache para no consultar res.users repetidamente durante la importación.
     */
    private Usuario resolverComercial(Integer odooUserId, Map<Integer, Usuario> cache) {
        if (odooUserId == null) {
            return null;
        }
        if (cache.containsKey(odooUserId)) {
            return cache.get(odooUserId);
        }
        Usuario usuario = null;
        String[] identidades = odooClienteRepository.findUserLoginAndEmail(odooUserId);
        if (identidades != null) {
            for (String identidad : identidades) {
                if (identidad != null) {
                    usuario = usuarioRepository.findByEmailIgnoreCase(identidad).orElse(null);
                    if (usuario != null) {
                        break;
                    }
                }
            }
        }
        cache.put(odooUserId, usuario);
        return usuario;
    }

    /**
     * Envía a Odoo los clientes dados de alta en la app (estadoSync = PENDENTE).
     * Cada cliente se crea siempre como un partner nuevo en Odoo (la deduplicación por CIF
     * ya se decide en el alta). Si tiene éxito queda SINCRONIZADO con su idOdoo; si falla, ERRO.
     *
     * @return resumen del envío (éxitos y errores)
     */
    @Transactional
    public SyncResult enviarClientesPendientes() {
        SyncResult result = new SyncResult();
        List<Cliente> pendientes = clienteRepository.findByEstadoSync(EstadoSync.PENDENTE);
        if (pendientes.isEmpty()) {
            log.info("[DB -> ODOO] No hay clientes pendientes de enviar");
            return result;
        }

        log.info("=== ENVIANDO {} CLIENTES PENDIENTES A ODOO ===", pendientes.size());
        inicializarCachesUbicacion(pendientes);

        for (Cliente cliente : pendientes) {
            try {
                enviarCliente(cliente);
                result.addExito();
            } catch (Exception e) {
                cliente.setEstadoSync(EstadoSync.ERRO);
                clienteRepository.save(cliente);
                result.addError(cliente.getId(), e.getMessage());
                log.error("[DB -> ODOO] Error enviando cliente {} ({}): {}",
                        cliente.getId(), cliente.getRazonSocial(), e.getMessage());
            }
        }

        log.info("=== ENVÍO DE CLIENTES A ODOO FINALIZADO: {} ===", result);
        return result;
    }

    /**
     * Envía un único cliente a Odoo de forma inmediata. Pensado para llamarse
     * justo después de guardar un cliente nuevo desde {@code POST /clientes},
     * para que la sincronización de la app deje al cliente confirmado en
     * Odoo en la misma vuelta y los pedidos asociados puedan resolver
     * inmediatamente su {@code partner_id}.
     *
     * Si Odoo está caído o el envío falla, se lanza la excepción al llamador
     * (que típicamente la captura y deja el cliente en PENDENTE para que el
     * scheduler periódico lo reintente). Nada se marca ERRO desde aquí; el
     * primer intento inmediato no debería gastar el "cupo" de error si la
     * causa es transitoria.
     *
     * Comparte transacción con el llamador: si se invoca desde dentro de
     * {@code @Transactional}, los cambios sobre la entidad (idOdoo,
     * estadoSync, fechaModificacion) se persisten en el mismo commit.
     */
    @Transactional
    public void enviarUno(Cliente cliente) {
        // Carga las caches de país y provincia que enviarCliente necesita.
        // Es un coste pequeño (1-2 lookups en Odoo) y solo para esta llamada.
        inicializarCachesUbicacion(List.of(cliente));
        enviarCliente(cliente);
    }

    /**
     * Crea un cliente en Odoo, le asigna su idOdoo y lo marca como SINCRONIZADO.
     */
    private void enviarCliente(Cliente cliente) {
        Integer vendorUserId = resolverVendedor(cliente);
        Integer idOdoo = odooClienteRepository.create(cliente, vendorUserId);
        cliente.setIdOdoo(String.valueOf(idOdoo));
        cliente.setEstadoSync(EstadoSync.SINCRONIZADO);
        cliente.setFechaModificacion(LocalDateTime.now());
        clienteRepository.save(cliente);
        log.info("[DB -> ODOO] Cliente enviado: {} -> idOdoo {}", cliente.getRazonSocial(), idOdoo);
    }

    /**
     * Resuelve el vendedor (user_id de Odoo) a partir del email del comercial del cliente.
     * Si el comercial no tiene email o no existe ese usuario en Odoo, devuelve null (no se asigna).
     */
    private Integer resolverVendedor(Cliente cliente) {
        if (cliente.getComercial() == null || cliente.getComercial().getEmail() == null) {
            return null;
        }
        Integer userId = odooClienteRepository.findUserIdByEmail(cliente.getComercial().getEmail());
        if (userId == null) {
            log.info("[DB -> ODOO] Sin vendedor en Odoo para el email {} (cliente {})",
                    cliente.getComercial().getEmail(), cliente.getRazonSocial());
        }
        return userId;
    }

    /**
     * Carga en el mapper los ids de Odoo del país por defecto y de las provincias de los
     * clientes a enviar, para poder rellenar country_id y state_id sin consultas repetidas.
     */
    private void inicializarCachesUbicacion(List<Cliente> clientes) {
        odooClienteMapper.clearCaches();
        Integer countryId = odooClienteRepository.findCountryIdByCode(odooClienteMapper.getCodigoPaisDefecto());
        if (countryId != null) {
            odooClienteMapper.cacheCountryId(odooClienteMapper.getPaisDefecto(), countryId);
        } else {
            log.warn("[DB -> ODOO] No se encontró el país '{}' (código {}) en Odoo; los clientes se enviarán sin país/provincia",
                    odooClienteMapper.getPaisDefecto(), odooClienteMapper.getCodigoPaisDefecto());
        }
        for (Cliente cliente : clientes) {
            String provincia = cliente.getProvincia();
            if (provincia != null && !provincia.isBlank() && odooClienteMapper.getCachedStateId(provincia) == null) {
                Integer stateId = odooClienteRepository.findStateIdByName(provincia, countryId);
                if (stateId != null) {
                    odooClienteMapper.cacheStateId(provincia, stateId);
                } else {
                    log.warn("[DB -> ODOO] Provincia '{}' no encontrada en Odoo (res.country.state); "
                            + "el cliente se enviará sin provincia", provincia);
                }
            }
        }
    }
}
