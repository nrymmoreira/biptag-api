package br.com.biptag.biptag_api;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;

import java.sql.CallableStatement;
import java.sql.ResultSet;
import java.sql.Types;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Testes de integracao entre a API (Java/JDBC) e os objetos PL/SQL da Fase 7:
 * packages, SQL dinamico e triggers. Rodam contra o Oracle do pipeline.
 */
@SpringBootTest
class OraclePlsqlIntegrationTests {

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Test
    void functionComSqlDinamicoChamadaPelaApi() {
        Integer totalItens = jdbcTemplate.queryForObject(
                "SELECT pkg_biptag_relatorios.fn_contar_por_status('ITEMS') FROM dual", Integer.class);
        Integer alertasAtivos = jdbcTemplate.queryForObject(
                "SELECT pkg_biptag_relatorios.fn_contar_por_status('ALERTS', 'active') FROM dual", Integer.class);

        assertEquals(5, totalItens);
        assertEquals(2, alertasAtivos);
    }

    @Test
    void procedureDeBuscaRetornaCursorParaAApi() {
        List<String> nomes = jdbcTemplate.execute((ConnectionCallback<List<String>>) conexao -> {
            String chamada = "{call pkg_biptag_relatorios.prc_buscar_itens("
                    + "p_status => ?, p_ordenar_por => ?, p_resultado => ?)}";
            try (CallableStatement cs = conexao.prepareCall(chamada)) {
                cs.setString(1, "active");
                cs.setString(2, "NOME");
                cs.registerOutParameter(3, Types.REF_CURSOR);
                cs.execute();

                List<String> resultado = new ArrayList<>();
                try (ResultSet rs = cs.getObject(3, ResultSet.class)) {
                    while (rs.next()) {
                        resultado.add(rs.getString("NAME"));
                    }
                }
                return resultado;
            }
        });

        assertEquals(3, nomes.size(), "Devem existir 3 itens com status active");
        assertTrue(nomes.contains("iPhone 14 Pro"), "O resultado deve trazer os itens da massa de dados");
    }

    @Test
    @Transactional
    void triggersAuditamESincronizamAoEncerrarAlerta() {
        Long alertaId = jdbcTemplate.queryForObject(
                "SELECT id FROM alerts WHERE item_id = 4 AND status = 'active'", Long.class);

        // Simula o encerramento feito pela API: um UPDATE comum via JDBC
        jdbcTemplate.update("UPDATE alerts SET status = 'canceled' WHERE id = ?", alertaId);

        String statusItem = jdbcTemplate.queryForObject(
                "SELECT status FROM items WHERE id = 4", String.class);
        Integer logsDepois = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM alert_audit_log WHERE alert_id = ? AND operacao = 'UPDATE' "
                        + "AND status_anterior = 'active' AND status_novo = 'canceled'",
                Integer.class, alertaId);

        assertEquals("active", statusItem, "A trigger deve devolver o item ao status active");
        assertTrue(logsDepois > 0, "A trigger deve registrar a auditoria do encerramento");
        // @Transactional desfaz as alteracoes ao final do teste
    }
}
