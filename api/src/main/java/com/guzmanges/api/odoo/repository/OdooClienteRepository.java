package com.guzmanges.api.odoo.repository;

import java.util.Arrays;
import java.util.List;
import java.util.Map;

import org.springframework.stereotype.Repository;

import com.guzmanges.api.entity.Cliente;
import com.guzmanges.api.odoo.client.OdooXmlRpcClient;
import com.guzmanges.api.odoo.mapper.OdooClienteMapper;
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
            "property_payment_term_id", "customer_payment_mode_id", "active");

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
     * Crea un cliente en Odoo.
     *
     * @param cliente cliente local a crear
     * @return id del registro creado en Odoo
     */
    public Integer create(Cliente cliente) {
        return client.create(MODEL, mapper.toOdooMap(cliente));
    }

    /**
     * Actualiza un cliente existente en Odoo.
     *
     * @param idOdoo  id del registro en Odoo
     * @param cliente cliente local con los datos a enviar
     * @return true si se actualizó correctamente
     */
    public Boolean update(int idOdoo, Cliente cliente) {
        return client.write(MODEL, idOdoo, mapper.toOdooMap(cliente));
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
     * Busca el id de un país en Odoo por su nombre.
     *
     * @param nombre nombre del país
     * @return id en Odoo o null si no existe
     */
    public Integer findCountryIdByName(String nombre) {
        if (nombre == null) {
            return null;
        }
        return client.searchOne("res.country", List.of(Arrays.asList("name", "=", nombre)));
    }

    /**
     * Busca el id de una provincia en Odoo por su nombre (opcionalmente dentro de un país).
     *
     * @param nombre    nombre de la provincia
     * @param countryId id del país en Odoo (puede ser null)
     * @return id en Odoo o null si no existe
     */
    public Integer findStateIdByName(String nombre, Integer countryId) {
        if (nombre == null) {
            return null;
        }
        List<Object> domain;
        if (countryId != null) {
            domain = List.of(
                    Arrays.asList("name", "=", nombre),
                    Arrays.asList("country_id", "=", countryId)
            );
        } else {
            domain = List.of(
                    Arrays.asList("name", "=", nombre)
            );
        }
        return client.searchOne("res.country.state", domain);
    }
}
