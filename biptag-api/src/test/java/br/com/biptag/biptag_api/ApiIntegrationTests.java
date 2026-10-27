package br.com.biptag.biptag_api;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.core.env.Environment;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Testes de integracao da API REST. Sobem a aplicacao completa em uma porta
 * aleatoria, conectada ao Oracle do pipeline, e chamam os endpoints por HTTP.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ApiIntegrationTests {

    @Autowired
    private Environment environment;

    private final HttpClient http = HttpClient.newHttpClient();
    private String baseUrl;

    @BeforeEach
    void configurarUrl() {
        baseUrl = "http://localhost:" + environment.getProperty("local.server.port");
    }

    private HttpResponse<String> get(String caminho) throws Exception {
        HttpRequest request = HttpRequest.newBuilder(URI.create(baseUrl + caminho)).GET().build();
        return http.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
    }

    @Test
    void listaCategoriasDoOracle() throws Exception {
        HttpResponse<String> resposta = get("/api/v1/categories");

        assertEquals(200, resposta.statusCode());
        assertTrue(resposta.body().contains("Documentos"), "A lista deve trazer as categorias da massa de dados");
    }

    @Test
    void listaItensDoOracle() throws Exception {
        HttpResponse<String> resposta = get("/api/v1/items");

        assertEquals(200, resposta.statusCode());
        assertTrue(resposta.body().contains("Carteira de couro"), "A lista deve trazer os itens da massa de dados");
    }

    @Test
    void escritaSemTokenEhBloqueada() throws Exception {
        HttpRequest request = HttpRequest.newBuilder(URI.create(baseUrl + "/api/v1/categories"))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString("{\"name\":\"Teste\"}"))
                .build();

        HttpResponse<String> resposta = http.send(request, HttpResponse.BodyHandlers.ofString());

        assertEquals(401, resposta.statusCode(), "POST sem token JWT deve ser recusado");
    }

    @Test
    void documentacaoOpenApiDisponivel() throws Exception {
        HttpResponse<String> resposta = get("/v3/api-docs");

        assertEquals(200, resposta.statusCode());
        assertTrue(resposta.body().contains("/api/v1/items"), "A especificacao OpenAPI deve listar os endpoints");
    }
}
