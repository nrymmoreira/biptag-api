# BipTag API

API REST do BipTag (Smart HAS), em Java 17 com Spring Boot, conectada a um banco Oracle.

## Estrutura

| Pasta | Conteúdo |
|---|---|
| `biptag-api/` | Código da API (Spring Boot, Maven) e `Dockerfile` |
| `database/` | Scripts Oracle: tabelas, dados de teste, packages, triggers e testes PL/SQL |
| `.github/workflows/ci-cd.yml` | Pipeline de CI/CD no GitHub Actions |

## Executar localmente

A conexão com o banco vem de variáveis de ambiente:

| Variável | Uso | Padrão |
|---|---|---|
| `DB_URL` | URL JDBC do Oracle | `jdbc:oracle:thin:@oracle.fiap.com.br:1521:ORCL` |
| `DB_USERNAME` | Usuário do banco | `RM556355` |
| `DB_PASSWORD` | Senha do banco | sem padrão (obrigatória) |

```bash
cd biptag-api
DB_PASSWORD=sua_senha ./mvnw spring-boot:run
```

A documentação dos endpoints fica em `http://localhost:8080/swagger-ui.html`.

## Pipeline de CI/CD

O workflow `CI/CD BipTag API` roda a cada push nas branches `main` e `fase-7-devops`
e em pull requests para a `main`.

1. **Build, banco Oracle e testes.** Sobe um Oracle XE em container, aplica os
   scripts da pasta `database/`, executa os testes PL/SQL e depois compila a API e
   roda os testes JUnit contra esse banco.
2. **Deploy.** Gera a imagem Docker da API, publica no GitHub Container Registry
   (`ghcr.io/<dono>/biptag-api`) e sobe um ambiente de homologação com Oracle,
   onde a imagem publicada é validada por testes de fumaça nos endpoints.
3. **Deploy no Oracle da FIAP (manual).** Pela opção *Run workflow*, aplica os
   packages e triggers no banco da FIAP usando os secrets `FIAP_DB_USER`,
   `FIAP_DB_PASSWORD` e `FIAP_DB_CONNECT`.

Cada execução gera um resumo na própria página do Actions e publica os logs do
banco, o log do Maven, os relatórios do Surefire e os logs da API como artefatos.
