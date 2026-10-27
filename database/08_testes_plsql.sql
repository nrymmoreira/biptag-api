SET SERVEROUTPUT ON SIZE UNLIMITED;

--------------------------------------------------------------------------------
-- 08_TESTES_PLSQL.SQL  (Fase 7 - testes automatizados do banco)
--
-- Executado pelo pipeline de CI/CD logo apos a carga dos scripts 01, 02, 06
-- e 07 em um banco Oracle limpo. Cada bloco valida um comportamento e, se a
-- verificacao falhar, lanca um erro que interrompe o pipeline.
--
-- Massa de dados esperada (script 02):
--   itens: 1 active, 2 lost, 3 active, 4 stolen, 5 active
--   alertas: #1 (item 2, active) e #2 (item 4, active)
--
-- Nao executar em um banco com dados reais: os testes 6 e 7 criam e encerram
-- um alerta para o item 3.
--------------------------------------------------------------------------------

-- Utilitario de verificacao usado pelos blocos abaixo
CREATE OR REPLACE PROCEDURE prc_teste_assert(
  p_condicao IN BOOLEAN,
  p_mensagem IN VARCHAR2
) IS
BEGIN
  IF p_condicao THEN
    DBMS_OUTPUT.PUT_LINE('[OK]    ' || p_mensagem);
  ELSE
    DBMS_OUTPUT.PUT_LINE('[FALHA] ' || p_mensagem);
    RAISE_APPLICATION_ERROR(-20900, 'Teste falhou: ' || p_mensagem);
  END IF;
END prc_teste_assert;
/

PROMPT
PROMPT ===== TESTE 1: objetos compilados e validos =====
DECLARE
  v_validos NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_validos
  FROM user_objects
  WHERE object_name IN ('PKG_BIPTAG_ALERTAS', 'PKG_BIPTAG_RELATORIOS',
                        'TRG_ALERTS_AUDITORIA', 'TRG_ALERTS_SINCRONIZA_ITEM')
    AND status = 'VALID';
  prc_teste_assert(v_validos = 6, 'Packages (spec e body) e triggers validos: ' || v_validos || ' de 6');
END;
/

PROMPT
PROMPT ===== TESTE 2: SQL dinamico com EXECUTE IMMEDIATE =====
BEGIN
  prc_teste_assert(pkg_biptag_relatorios.fn_contar_por_status('ITEMS') = 5,
                   'Total de itens = 5');
  prc_teste_assert(pkg_biptag_relatorios.fn_contar_por_status('items', 'ACTIVE') = 3,
                   'Itens com status active = 3 (nome de tabela e status sem diferenciar maiusculas)');
  prc_teste_assert(pkg_biptag_relatorios.fn_contar_por_status('ALERTS', 'active') = 2,
                   'Alertas ativos = 2');
END;
/

PROMPT
PROMPT ===== TESTE 3: SQL dinamico com OPEN FOR ... USING (busca flexivel) =====
DECLARE
  v_cursor    SYS_REFCURSOR;
  v_id        items.id%TYPE;
  v_nome      items.name%TYPE;
  v_categoria category.name%TYPE;
  v_status    items.status%TYPE;
  v_tag       items.tag_id%TYPE;
  v_usuario   items.user_id%TYPE;
  v_criado    items.created_at%TYPE;
  v_total     NUMBER;

  FUNCTION contar(p_cursor IN OUT SYS_REFCURSOR) RETURN NUMBER IS
    n NUMBER := 0;
  BEGIN
    LOOP
      FETCH p_cursor INTO v_id, v_nome, v_categoria, v_status, v_tag, v_usuario, v_criado;
      EXIT WHEN p_cursor%NOTFOUND;
      n := n + 1;
    END LOOP;
    CLOSE p_cursor;
    RETURN n;
  END contar;
BEGIN
  pkg_biptag_relatorios.prc_buscar_itens(p_resultado => v_cursor);
  v_total := contar(v_cursor);
  prc_teste_assert(v_total = 5, 'Busca sem filtros retorna 5 itens');

  pkg_biptag_relatorios.prc_buscar_itens(p_status => 'active', p_ordenar_por => 'NOME', p_resultado => v_cursor);
  v_total := contar(v_cursor);
  prc_teste_assert(v_total = 3, 'Busca por status active retorna 3 itens');
  DBMS_OUTPUT.PUT_LINE('        SQL gerado: ' || pkg_biptag_relatorios.fn_ultimo_sql);

  pkg_biptag_relatorios.prc_buscar_itens(p_categoria_id => 1, p_resultado => v_cursor);
  v_total := contar(v_cursor);
  prc_teste_assert(v_total = 1, 'Busca pela categoria 1 (Eletronicos) retorna 1 item');

  pkg_biptag_relatorios.prc_buscar_itens(p_termo => 'chave', p_ordenar_por => 'categoria', p_resultado => v_cursor);
  v_total := contar(v_cursor);
  prc_teste_assert(v_total = 1, 'Busca pelo termo "chave" retorna 1 item');

  pkg_biptag_relatorios.prc_buscar_itens(
    p_user_id => '44444444-4444-4444-4444-444444444444', p_status => 'stolen', p_resultado => v_cursor);
  v_total := contar(v_cursor);
  prc_teste_assert(v_total = 1, 'Busca combinando usuario e status retorna 1 item');
END;
/

PROMPT
PROMPT ===== TESTE 4: protecao contra entrada invalida no SQL dinamico =====
DECLARE
  v_total  NUMBER;
  v_cursor SYS_REFCURSOR;
BEGIN
  BEGIN
    v_total := pkg_biptag_relatorios.fn_contar_por_status('APP_USERS; DROP TABLE items');
    prc_teste_assert(FALSE, 'Tabela fora da lista deveria ser recusada');
  EXCEPTION
    WHEN OTHERS THEN
      prc_teste_assert(SQLCODE = -20011, 'Tabela fora da lista recusada com ORA-20011');
  END;

  BEGIN
    pkg_biptag_relatorios.prc_buscar_itens(p_ordenar_por => 'name; DELETE FROM items', p_resultado => v_cursor);
    prc_teste_assert(FALSE, 'Ordenacao invalida deveria ser recusada');
  EXCEPTION
    WHEN OTHERS THEN
      prc_teste_assert(SQLCODE = -20010, 'Ordenacao fora da lista recusada com ORA-20010');
  END;
END;
/

PROMPT
PROMPT ===== TESTE 5: functions migradas para o package =====
BEGIN
  prc_teste_assert(pkg_biptag_relatorios.fn_taxa_recuperacao_usuario('22222222-2222-2222-2222-222222222222') = 0,
                   'Taxa de recuperacao da Maria = 0 (devolucao ainda nao concluida)');
  prc_teste_assert(pkg_biptag_relatorios.fn_taxa_recuperacao_usuario('ffffffff-ffff-ffff-ffff-ffffffffffff') IS NULL,
                   'Taxa de recuperacao de usuario inexistente = NULL');
  prc_teste_assert(INSTR(pkg_biptag_relatorios.fn_resumo_item_formatado(2), 'Carteira de couro') = 1,
                   'Resumo do item 2 comeca pelo nome do item');
  prc_teste_assert(pkg_biptag_relatorios.fn_resumo_item_formatado(999) = 'ITEM NAO ENCONTRADO',
                   'Resumo de item inexistente');
END;
/

PROMPT
PROMPT ===== TESTE 6: registrar alerta pelo package + trigger de auditoria =====
DECLARE
  v_alert_id   alerts.id%TYPE;
  v_status     items.status%TYPE;
  v_logs       NUMBER;
  v_notif      NUMBER;
BEGIN
  pkg_biptag_alertas.prc_registrar_alerta(
    p_item_id       => 3,
    p_type          => 'lost',
    p_incident_date => '2026-10-20',
    p_description   => 'Teste automatizado do pipeline',
    p_alert_id      => v_alert_id
  );

  SELECT status INTO v_status FROM items WHERE id = 3;
  prc_teste_assert(v_status = 'lost', 'Item 3 passou para lost');

  SELECT COUNT(*) INTO v_logs
  FROM alert_audit_log
  WHERE alert_id = v_alert_id AND operacao = 'INSERT' AND status_novo = 'active';
  prc_teste_assert(v_logs = 1, 'Trigger de auditoria registrou o INSERT do alerta #' || v_alert_id);

  SELECT COUNT(*) INTO v_notif
  FROM notifications
  WHERE user_id = '33333333-3333-3333-3333-333333333333' AND title = 'Alerta registrado';
  prc_teste_assert(v_notif = 1, 'Notificacao de alerta registrado criada para o dono');

  BEGIN
    pkg_biptag_alertas.prc_registrar_alerta(
      p_item_id => 3, p_type => 'lost', p_incident_date => '2026-10-21', p_alert_id => v_alert_id);
    prc_teste_assert(FALSE, 'Alerta duplicado deveria ser recusado');
  EXCEPTION
    WHEN OTHERS THEN
      prc_teste_assert(SQLCODE = -20003, 'Alerta duplicado recusado com ORA-20003');
  END;
END;
/

PROMPT
PROMPT ===== TESTE 7: encerrar alerta + trigger de automacao =====
DECLARE
  v_alert_id alerts.id%TYPE;
  v_status   items.status%TYPE;
  v_log      alert_audit_log%ROWTYPE;
  v_notif    NUMBER;
BEGIN
  SELECT id INTO v_alert_id
  FROM alerts
  WHERE item_id = 3 AND status = 'active';

  pkg_biptag_alertas.prc_encerrar_alerta(v_alert_id, 'resolved');

  SELECT status INTO v_status FROM items WHERE id = 3;
  prc_teste_assert(v_status = 'active', 'Trigger devolveu o item 3 para active');

  SELECT * INTO v_log
  FROM alert_audit_log
  WHERE alert_id = v_alert_id AND operacao = 'UPDATE';
  prc_teste_assert(v_log.status_anterior = 'active' AND v_log.status_novo = 'resolved',
                   'Auditoria registrou a mudanca active -> resolved');

  SELECT COUNT(*) INTO v_notif
  FROM notifications
  WHERE user_id = '33333333-3333-3333-3333-333333333333' AND title = 'Alerta encerrado';
  prc_teste_assert(v_notif = 1, 'Notificacao de alerta encerrado criada pela trigger');

  BEGIN
    pkg_biptag_alertas.prc_encerrar_alerta(v_alert_id, 'resolved');
    prc_teste_assert(FALSE, 'Encerrar alerta ja encerrado deveria ser recusado');
  EXCEPTION
    WHEN OTHERS THEN
      prc_teste_assert(SQLCODE = -20006, 'Alerta ja encerrado recusado com ORA-20006');
  END;
END;
/

PROMPT
PROMPT ===== DEMONSTRACAO: painel de status e relatorio do usuario =====
BEGIN
  pkg_biptag_relatorios.prc_painel_status;
  pkg_biptag_relatorios.prc_relatorio_usuario('33333333-3333-3333-3333-333333333333');
END;
/

PROMPT
PROMPT ===== LOG DE AUDITORIA =====
COLUMN operacao FORMAT A8
COLUMN status_anterior FORMAT A10
COLUMN status_novo FORMAT A10
COLUMN origem FORMAT A40
SELECT id, alert_id, item_id, operacao, status_anterior, status_novo, origem
FROM alert_audit_log
ORDER BY id;

DROP PROCEDURE prc_teste_assert;

PROMPT
PROMPT ===== TODOS OS TESTES PL/SQL PASSARAM =====
