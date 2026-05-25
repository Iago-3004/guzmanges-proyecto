package com.guzmanges.api.odoo.repository;

import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.springframework.stereotype.Repository;

import com.guzmanges.api.entity.Cliente;
import com.guzmanges.api.odoo.client.OdooXmlRpcClient;
import com.guzmanges.api.odoo.mapper.OdooClienteMapper;
import com.guzmanges.api.odoo.util.OdooValueUtil;
import com.guzmanges.api.util.VatUtil;

import lombok.RequiredArgsConstructor;

/**
 * Acceso a los clientes de Odoo (modelo res.partner).
 * Permite leer los clientes (para importarlos) y crear/actualizarlos (para enviarlos).
 */
@Repository
@RequiredArgsConstructor
public class OdooClienteRepository {

    private static final String MODEL = "res.partner";

    /** Campos que se leen de cada cliente de Odoo. */
    private static final List<String> FIELDS = List.of(
            "id", "name", "vat", "comercial", "street", "city", "zip", "state_id",
            "phone", "mobile", "email", "property_account_position_id",
            "property_payment_term_id", "customer_payment_mode_id", "user_id", "write_date", "active");

    private final OdooXmlRpcClient client;
    private final OdooClienteMapper mapper;

    /**
     * Obtiene los clientes de Odoo (partners con customer_rank > 0) de la empresa por defecto
     * del usuario de la API más los compartidos.
     *
     * @return lista de registros de Odoo
     */
    public List<Map<String, Object>> findClientes() {
        Integer companyId = client.getDefaultCompanyId();
        List<Object> domain;
        if (companyId != null) {
            // (company_id = empresa por defecto OR company_id = false)
            //   AND customer_rank > 0 AND active in [true, false] (incluye archivados)
            domain = List.of(
                    "|",
                    Arrays.asList("company_id", "=", companyId),
                    Arrays.asList("company_id", "=", false),
                    Arrays.asList("customer_rank", ">", 0),
                    Arrays.asList("active", "in", List.of(true, false))
            );
        } else {
            domain = List.of(
                    Arrays.asList("customer_rank", ">", 0),
                    Arrays.asList("active", "in", List.of(true, false))
            );
        }
        return client.searchRead(MODEL, domain, FIELDS);
    }

    /**
     * Lee un cliente de Odoo por su id.
     *
     * @param idOdoo id del registro en Odoo
     * @return el registro, o null si no existe
     */
    public Map<String, Object> findById(int idOdoo) {
        List<Map<String, Object>> resultado = client.read(MODEL, List.of(idOdoo), FIELDS);
        return resultado.isEmpty() ? null : resultado.get(0);
    }

    /**
     * De una lista de ids, devuelve los que todavía existen como res.partner en Odoo
     * (activos o archivados). Se usa para confirmar borrados: un id que NO vuelve ha sido
     * eliminado por completo en Odoo (un partner archivado sí se devuelve, no es un borrado).
     *
     * @param ids ids de Odoo a comprobar
     * @return conjunto de ids que siguen existiendo
     */
    public Set<Integer> findExistingIds(List<Integer> ids) {
        if (ids == null || ids.isEmpty()) {
            return Set.of();
        }
        List<Object> domain = List.of(
                Arrays.asList("id", "in", ids),
                Arrays.asList("active", "in", List.of(true, false))
        );
        return new HashSet<>(client.search(MODEL, domain));
    }

    /**
     * Crea un cliente en Odoo.
     *
     * @param cliente      cliente local a crear
     * @param vendorUserId id del vendedor en Odoo, o null para no asignarlo
     * @return id del registro creado en Odoo
     */
    public Integer create(Cliente cliente, Integer vendorUserId) {
        return client.create(MODEL, mapper.toOdooMap(cliente, vendorUserId));
    }

    /**
     * Actualiza un cliente existente en Odoo.
     *
     * @param idOdoo       id del registro en Odoo
     * @param cliente      cliente local con los datos a enviar
     * @param vendorUserId id del vendedor en Odoo, o null para no asignarlo
     * @return true si se actualizó correctamente
     */
    public Boolean update(int idOdoo, Cliente cliente, Integer vendorUserId) {
        return client.write(MODEL, idOdoo, mapper.toOdooMap(cliente, vendorUserId));
    }

    /**
     * Busca el id de un usuario de Odoo (res.users) por su login/email.
     * Se usa para asignar el vendedor (user_id) del cliente al enviarlo.
     *
     * @param email email/login del usuario
     * @return id del usuario en Odoo o null si no existe
     */
    public Integer findUserIdByEmail(String email) {
        if (email == null || email.isBlank()) {
            return null;
        }
        // Coincidencia por login O por email (según cómo esté dado de alta el usuario en Odoo)
        List<Object> domain = List.of(
                "|",
                Arrays.asList("login", "=", email),
                Arrays.asList("email", "=", email)
        );
        return client.searchOne("res.users", domain);
    }

    /**
     * Obtiene el login y el email de un usuario de Odoo (res.users) por su id.
     * Se usa al importar para mapear el vendedor de Odoo al comercial local por su email.
     *
     * @param userId id del usuario en Odoo
     * @return array {login, email} (cada uno puede ser null), o null si el usuario no existe
     */
    public String[] findUserLoginAndEmail(int userId) {
        List<Map<String, Object>> resultado = client.read("res.users", List.of(userId), List.of("login", "email"));
        if (resultado.isEmpty()) {
            return null;
        }
        Map<String, Object> usuario = resultado.get(0);
        return new String[]{
                OdooValueUtil.getStringValue(usuario, "login"),
                OdooValueUtil.getStringValue(usuario, "email")
        };
    }

    /**
     * Busca el id de un cliente en Odoo por su CIF/VAT (para evitar duplicados al enviar).
     *
     * @param cif CIF del cliente
     * @return id en Odoo o null si no existe
     */
    public Integer findIdByVat(String cif) {
        String vat = VatUtil.formatVat(cif);
        if (vat == null) {
            return null;
        }
        return client.searchOne(MODEL, List.of(Arrays.asList("vat", "=", vat)));
    }

    /**
     * Busca el id de un país en Odoo por su código ISO (campo "code", ej: "ES").
     * Se usa el código y no el nombre porque el nombre del país es traducible y la
     * búsqueda por nombre falla si el usuario de la API resuelve en otro idioma.
     *
     * @param codigo código ISO del país (ej: "ES")
     * @return id en Odoo o null si no existe
     */
    public Integer findCountryIdByCode(String codigo) {
        if (codigo == null || codigo.isBlank()) {
            return null;
        }
        return client.searchOne("res.country", List.of(Arrays.asList("code", "=ilike", codigo)));
    }

    /**
     * Busca el id de una provincia en Odoo por su nombre (opcionalmente dentro de un país).
     * La comparación usa "ilike" (ignora mayúsculas y permite coincidencia parcial), de modo
     * que "coruña" o "Coruña" resuelven aunque en Odoo figure como "A Coruña". Si se indica el
     * país, se acota a él; si así no se encuentra, se reintenta sin acotar al país.
     *
     * @param nombre    nombre de la provincia
     * @param countryId id del país en Odoo (puede ser null)
     * @return id en Odoo o null si no existe
     */
    public Integer findStateIdByName(String nombre, Integer countryId) {
        if (nombre == null || nombre.isBlank()) {
            return null;
        }
        if (countryId != null) {
            Integer stateId = client.searchOne("res.country.state", List.of(
                    Arrays.asList("country_id", "=", countryId),
                    Arrays.asList("name", "ilike", nombre)
            ));
            if (stateId != null) {
                return stateId;
            }
        }
        // Sin país (o no encontrada dentro del país): se busca solo por nombre
        return client.searchOne("res.country.state", List.of(Arrays.asList("name", "ilike", nombre)));
    }
}
