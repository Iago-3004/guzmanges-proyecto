package com.guzmanges.api.odoo.mapper;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Function;

import org.springframework.stereotype.Component;

import com.guzmanges.api.entity.Cliente;
import com.guzmanges.api.entity.CondicionPago;
import com.guzmanges.api.entity.EstadoSync;
import com.guzmanges.api.entity.ModoPago;
import com.guzmanges.api.entity.Usuario;
import com.guzmanges.api.odoo.util.OdooValueUtil;
import com.guzmanges.api.util.VatUtil;

/**
 * Conversión entre la entidad Cliente y el modelo res.partner de Odoo.
 *
 * Solo se mapean los campos relevantes para este proyecto; no se tratan los campos
 * propios de otros addons (Estrella Galicia) ni la estructura padre-hijo de Odoo.
 * El nombre comercial usa el campo "comercial" de la localización española (l10n_es_partner).
 */
@Component
public class OdooClienteMapper {

    /** País por defecto que se envía a Odoo para los clientes nuevos. */
    private static final String PAIS_DEFECTO = "España";

    /**
     * Código ISO del país por defecto. Se usa para resolver el country_id en Odoo,
     * porque el nombre del país es traducible y la búsqueda por nombre falla si el
     * usuario de la API resuelve en otro idioma; el código no es traducible.
     */
    private static final String CODIGO_PAIS_DEFECTO = "ES";

    /** Formato de las fechas que devuelve Odoo (ej: write_date), en UTC. */
    private static final DateTimeFormatter ODOO_DATETIME = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    // Caches nombre -> id de Odoo, para resolver país y provincia al enviar (evita consultas repetidas)
    private final Map<String, Integer> cacheCountryId = new ConcurrentHashMap<>();
    private final Map<String, Integer> cacheStateId = new ConcurrentHashMap<>();

    /**
     * Construye una entidad Cliente a partir de los datos de un res.partner de Odoo.
     *
     * @param odooData          datos del registro de Odoo (search_read)
     * @param condicionResolver función para resolver la CondicionPago local por su idOdoo
     * @param modoResolver      función para resolver el ModoPago local por su idOdoo
     * @param comercialResolver función para resolver el Usuario local a partir del id del
     *                          vendedor (user_id) de Odoo; devuelve null si no hay correspondencia
     * @return el Cliente poblado (estadoSync = SINCRONIZADO)
     */
    public Cliente fromOdooToCliente(Map<String, Object> odooData,
                                     Function<String, CondicionPago> condicionResolver,
                                     Function<String, ModoPago> modoResolver,
                                     Function<Integer, Usuario> comercialResolver) {
        Cliente cliente = new Cliente();
        cliente.setIdOdoo(String.valueOf(((Number) odooData.get("id")).longValue()));

        String name = OdooValueUtil.getStringValue(odooData, "name");
        cliente.setRazonSocial(name != null ? name : "Sin nombre");

        // CIF: Odoo lo guarda con prefijo "ES"; lo quitamos para la BD local
        String vat = OdooValueUtil.getStringValue(odooData, "vat");
        if (vat != null) {
            cliente.setCif(vat.toUpperCase().startsWith("ES") && vat.length() > 2 ? vat.substring(2) : vat);
        }

        // El nombre comercial es obligatorio en local; si Odoo no lo trae, se usa la razón social
        String nombreComercial = OdooValueUtil.getStringValue(odooData, "comercial");
        cliente.setNombreComercial(nombreComercial != null ? nombreComercial : cliente.getRazonSocial());

        cliente.setDireccion(OdooValueUtil.getStringValue(odooData, "street"));
        cliente.setLocalidad(OdooValueUtil.getStringValue(odooData, "city"));
        cliente.setCodigoPostal(OdooValueUtil.getStringValue(odooData, "zip"));
        cliente.setProvincia(nombreDeMany2one(odooData.get("state_id")));
        cliente.setTelefono(OdooValueUtil.getStringValue(odooData, "phone"));
        cliente.setMovil(OdooValueUtil.getStringValue(odooData, "mobile"));
        cliente.setEmail(OdooValueUtil.getStringValue(odooData, "email"));
        cliente.setPosicionFiscal(nombreDeMany2one(odooData.get("property_account_position_id")));

        // Condición y modo de pago: se resuelven a la entidad local por su idOdoo
        String condIdOdoo = idDeMany2one(odooData.get("property_payment_term_id"));
        if (condIdOdoo != null && condicionResolver != null) {
            cliente.setCondicionPago(condicionResolver.apply(condIdOdoo));
        }
        String modoIdOdoo = idDeMany2one(odooData.get("customer_payment_mode_id"));
        if (modoIdOdoo != null && modoResolver != null) {
            cliente.setModoPago(modoResolver.apply(modoIdOdoo));
        }

        // Comercial: se resuelve desde el vendedor (user_id) de Odoo. Si Odoo no tiene vendedor
        // o ese vendedor no es usuario de la app, queda null (Odoo es la fuente de verdad).
        Object userRaw = odooData.get("user_id");
        Integer odooUserId = (userRaw instanceof Object[] arr && arr.length > 0)
                ? ((Number) arr[0]).intValue() : null;
        cliente.setComercial(comercialResolver != null && odooUserId != null
                ? comercialResolver.apply(odooUserId) : null);

        boolean activo = odooData.get("active") instanceof Boolean b ? b : true;
        cliente.setActivo(activo);
        cliente.setEstadoSync(EstadoSync.SINCRONIZADO);
        cliente.setFechaModificacion(LocalDateTime.now());
        cliente.setFechaModificacionOdoo(parseFechaOdoo(odooData.get("write_date")));
        return cliente;
    }

    /**
     * Convierte una fecha de Odoo (cadena "yyyy-MM-dd HH:mm:ss") a LocalDateTime.
     *
     * @param valor valor del campo de Odoo
     * @return la fecha, o null si está vacía o no se puede interpretar
     */
    private LocalDateTime parseFechaOdoo(Object valor) {
        if (!(valor instanceof String texto) || "false".equals(texto) || texto.isEmpty()) {
            return null;
        }
        try {
            return LocalDateTime.parse(texto, ODOO_DATETIME);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Construye el Map de valores para crear o actualizar un res.partner en Odoo.
     *
     * @param cliente      cliente local a enviar
     * @param vendorUserId id del vendedor (res.users) en Odoo, o null para no asignarlo
     * @return Map con los campos de Odoo
     */
    public Map<String, Object> toOdooMap(Cliente cliente, Integer vendorUserId) {
        Map<String, Object> values = new HashMap<>();
        values.put("name", cliente.getRazonSocial());
        values.put("is_company", true);
        values.put("customer_rank", 1);
        values.put("active", true);
        values.put("vat", VatUtil.formatVat(cliente.getCif()));

        if (cliente.getNombreComercial() != null && !cliente.getNombreComercial().isEmpty()) {
            values.put("comercial", cliente.getNombreComercial());
        }

        ponerOFalse(values, "street", cliente.getDireccion());
        ponerOFalse(values, "city", cliente.getLocalidad());
        ponerOFalse(values, "zip", cliente.getCodigoPostal());
        ponerOFalse(values, "phone", cliente.getTelefono());
        ponerOFalse(values, "mobile", cliente.getMovil());
        ponerOFalse(values, "email", cliente.getEmail());

        Integer countryId = getCachedCountryId(PAIS_DEFECTO);
        if (countryId != null) {
            values.put("country_id", countryId);
        }
        Integer stateId = getCachedStateId(cliente.getProvincia());
        if (stateId != null) {
            values.put("state_id", stateId);
        }

        if (cliente.getCondicionPago() != null && cliente.getCondicionPago().getIdOdoo() != null) {
            values.put("property_payment_term_id", Integer.parseInt(cliente.getCondicionPago().getIdOdoo()));
        }
        if (cliente.getModoPago() != null && cliente.getModoPago().getIdOdoo() != null) {
            values.put("customer_payment_mode_id", Integer.parseInt(cliente.getModoPago().getIdOdoo()));
        }

        // Vendedor (salesperson) en Odoo, resuelto por el email del comercial; si no hay, no se asigna
        if (vendorUserId != null) {
            values.put("user_id", vendorUserId);
        }

        return values;
    }

    /** País por defecto que se asigna a los clientes enviados a Odoo. */
    public String getPaisDefecto() {
        return PAIS_DEFECTO;
    }

    /** Código ISO del país por defecto, para resolver su country_id en Odoo. */
    public String getCodigoPaisDefecto() {
        return CODIGO_PAIS_DEFECTO;
    }

    public void cacheCountryId(String nombrePais, Integer countryId) {
        if (nombrePais != null && countryId != null) {
            cacheCountryId.put(nombrePais.toLowerCase(), countryId);
        }
    }

    public Integer getCachedCountryId(String nombrePais) {
        return nombrePais == null ? null : cacheCountryId.get(nombrePais.toLowerCase());
    }

    public void cacheStateId(String nombreProvincia, Integer stateId) {
        if (nombreProvincia != null && stateId != null) {
            cacheStateId.put(nombreProvincia.toLowerCase(), stateId);
        }
    }

    public Integer getCachedStateId(String nombreProvincia) {
        return nombreProvincia == null ? null : cacheStateId.get(nombreProvincia.toLowerCase());
    }

    public void clearCaches() {
        cacheCountryId.clear();
        cacheStateId.clear();
    }

    /**
     * Extrae el nombre de un campo many2one de Odoo, que llega como [id, "nombre"] o false.
     */
    private String nombreDeMany2one(Object value) {
        if (value instanceof Object[] arr && arr.length > 1) {
            return (String) arr[1];
        }
        return null;
    }

    /**
     * Extrae el id (como String) de un campo many2one de Odoo, que llega como [id, "nombre"] o false.
     */
    private String idDeMany2one(Object value) {
        if (value instanceof Object[] arr && arr.length > 0) {
            return String.valueOf(((Number) arr[0]).longValue());
        }
        return null;
    }

    /**
     * Pone el valor en el Map si no es vacío; en caso contrario pone false (para limpiarlo en Odoo).
     */
    private void ponerOFalse(Map<String, Object> values, String campo, String valor) {
        values.put(campo, (valor != null && !valor.isEmpty()) ? valor : false);
    }
}
