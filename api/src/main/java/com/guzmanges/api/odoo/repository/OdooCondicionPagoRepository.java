package com.guzmanges.api.odoo.repository;

import java.util.Arrays;
import java.util.List;
import java.util.Map;

import org.springframework.stereotype.Repository;

import com.guzmanges.api.odoo.client.OdooXmlRpcClient;

import lombok.RequiredArgsConstructor;

/**
 * Acceso de lectura a las condiciones de pago de Odoo (modelo account.payment.term).
 * Odoo es la fuente de verdad: estas condiciones solo se leen para reflejarlas en la BD local.
 */
@Repository
@RequiredArgsConstructor
public class OdooCondicionPagoRepository {

    private static final String MODEL = "account.payment.term";

    private final OdooXmlRpcClient client;

    /**
     * Obtiene las condiciones de pago de Odoo de la empresa por defecto del usuario de la API
     * (más las compartidas, sin empresa), incluidas las archivadas.
     *
     * @return lista de registros de Odoo (cada uno con id, name y active)
     */
    public List<Map<String, Object>> findAll() {
        Integer companyId = client.getDefaultCompanyId();
        List<Object> domain;
        if (companyId != null) {
            // (company_id = empresa por defecto OR company_id = false) AND active in [true, false]
            domain = List.of(
                    "|",
                    Arrays.asList("company_id", "=", companyId),
                    Arrays.asList("company_id", "=", false),
                    Arrays.asList("active", "in", List.of(true, false))
            );
        } else {
            domain = List.of(
                    Arrays.asList("active", "in", List.of(true, false))
            );
        }
        List<String> fields = List.of("id", "name", "active");
        return client.searchRead(MODEL, domain, fields);
    }
}
