# Banco de dados Oracle do BipTag

Scripts do banco Oracle usado pela API, na ordem de execução.

| Script | Conteúdo |
|---|---|
| `01_ddl_oracle.sql` | 11 tabelas, chaves, restrições `CHECK`/`UNIQUE` e índices (Fase 6) |
| `02_dados_simulados.sql` | Massa de dados de teste (Fase 6) |
| `04_functions.sql` | Functions avulsas da Fase 6, mantidas como histórico |
| `05_procedures.sql` | Procedures avulsas da Fase 6, mantidas como histórico |
| `06_packages.sql` | Packages `PKG_BIPTAG_ALERTAS` e `PKG_BIPTAG_RELATORIOS`, com as rotinas da Fase 6 e as novas rotinas de SQL dinâmico (Fase 7) |
| `07_triggers.sql` | Tabela `ALERT_AUDIT_LOG` e as triggers `TRG_ALERTS_AUDITORIA` e `TRG_ALERTS_SINCRONIZA_ITEM` (Fase 7) |
| `08_testes_plsql.sql` | Testes automatizados dos packages e triggers, executados pelo pipeline |
| `deploy_db.sh` | Aplica os scripts com o SQL*Plus e para no primeiro erro |

A partir da Fase 7, as rotinas de negócio são chamadas pelos packages. Os scripts
`04` e `05` continuam no repositório para registrar a evolução do projeto.

## Executar manualmente

```bash
./deploy_db.sh "usuario/senha@//host:1521/servico" ./logs \
  01_ddl_oracle.sql 02_dados_simulados.sql 06_packages.sql 07_triggers.sql
```

Em um banco que já tem as tabelas, basta aplicar `06_packages.sql` e
`07_triggers.sql`. O script `08_testes_plsql.sql` cria e encerra um alerta de
teste, por isso deve rodar só em bancos de teste.

## Exemplos de uso

```sql
-- SQL dinâmico: itens ativos, ordenados por nome
VARIABLE rc REFCURSOR
EXEC pkg_biptag_relatorios.prc_buscar_itens(p_status => 'active', p_ordenar_por => 'NOME', p_resultado => :rc)
PRINT rc

-- SQL dinâmico: contagem por status em uma tabela monitorada
SELECT pkg_biptag_relatorios.fn_contar_por_status('ALERTS', 'active') FROM dual;

-- Painel de status de todas as tabelas monitoradas
EXEC pkg_biptag_relatorios.prc_painel_status

-- Encerrar um alerta (as triggers atualizam o item, auditam e notificam)
EXEC pkg_biptag_alertas.prc_encerrar_alerta(1, 'resolved')

SELECT * FROM alert_audit_log ORDER BY id;
```
