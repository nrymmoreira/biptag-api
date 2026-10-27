SET SERVEROUTPUT ON;

--------------------------------------------------------------------------------
-- 06_PACKAGES.SQL  (Fase 7 - Consolidacao em Oracle PL/SQL)
--
-- Agrupa as functions e procedures criadas na Fase 6 em dois packages e
-- acrescenta as rotinas novas com SQL dinamico.
--
--   PKG_BIPTAG_ALERTAS
--     - prc_registrar_alerta  (migrada do script 05)
--     - prc_encerrar_alerta   (nova)
--
--   PKG_BIPTAG_RELATORIOS
--     - fn_taxa_recuperacao_usuario (migrada do script 04)
--     - fn_resumo_item_formatado    (migrada do script 04)
--     - prc_relatorio_usuario       (migrada do script 05)
--     - prc_buscar_itens            (nova, SQL dinamico com OPEN FOR ... USING)
--     - fn_contar_por_status        (nova, SQL dinamico com EXECUTE IMMEDIATE)
--     - prc_painel_status           (nova, SQL dinamico com cursor de referencia)
--     - fn_ultimo_sql               (nova, devolve o ultimo SQL dinamico gerado)
--
-- Os scripts 04 e 05 ficam no repositorio como historico da Fase 6. A partir
-- desta fase, as rotinas sao mantidas e chamadas pelos packages.
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- PACKAGE 1: PKG_BIPTAG_ALERTAS (especificacao)
-- Concentra as regras de negocio do ciclo de vida de um alerta de perda ou
-- furto: abertura e encerramento.
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_biptag_alertas AS

  -- Codigos de erro de negocio expostos pelo package
  c_err_item_inexistente   CONSTANT PLS_INTEGER := -20001;
  c_err_tipo_invalido      CONSTANT PLS_INTEGER := -20002;
  c_err_alerta_duplicado   CONSTANT PLS_INTEGER := -20003;
  c_err_alerta_inexistente CONSTANT PLS_INTEGER := -20005;
  c_err_alerta_encerrado   CONSTANT PLS_INTEGER := -20006;
  c_err_status_invalido    CONSTANT PLS_INTEGER := -20007;

  -- Registra um alerta de perda ou furto, atualiza o status do item e cria a
  -- notificacao para o dono na mesma transacao. Devolve o id do alerta.
  PROCEDURE prc_registrar_alerta(
    p_item_id         IN  items.id%TYPE,
    p_type            IN  alerts.type%TYPE,
    p_incident_date   IN  alerts.incident_date%TYPE,
    p_last_seen_lat   IN  alerts.last_seen_lat%TYPE     DEFAULT NULL,
    p_last_seen_lng   IN  alerts.last_seen_lng%TYPE     DEFAULT NULL,
    p_last_seen_addr  IN  alerts.last_seen_address%TYPE DEFAULT NULL,
    p_description     IN  alerts.description%TYPE       DEFAULT NULL,
    p_alert_id        OUT alerts.id%TYPE
  );

  -- Encerra um alerta ativo como 'resolved' ou 'canceled'. A atualizacao do
  -- item, o log de auditoria e a notificacao ficam a cargo das triggers
  -- definidas no script 07.
  PROCEDURE prc_encerrar_alerta(
    p_alert_id    IN alerts.id%TYPE,
    p_novo_status IN alerts.status%TYPE DEFAULT 'resolved'
  );

END pkg_biptag_alertas;
/

--------------------------------------------------------------------------------
-- PACKAGE 1: PKG_BIPTAG_ALERTAS (corpo)
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY pkg_biptag_alertas AS

  PROCEDURE prc_registrar_alerta(
    p_item_id         IN  items.id%TYPE,
    p_type            IN  alerts.type%TYPE,
    p_incident_date   IN  alerts.incident_date%TYPE,
    p_last_seen_lat   IN  alerts.last_seen_lat%TYPE     DEFAULT NULL,
    p_last_seen_lng   IN  alerts.last_seen_lng%TYPE     DEFAULT NULL,
    p_last_seen_addr  IN  alerts.last_seen_address%TYPE DEFAULT NULL,
    p_description     IN  alerts.description%TYPE       DEFAULT NULL,
    p_alert_id        OUT alerts.id%TYPE
  ) IS
    v_item_owner      app_users.id%TYPE;
    v_item_name       items.name%TYPE;
    v_alertas_ativos  NUMBER;

    e_item_inexistente  EXCEPTION;
    e_tipo_invalido     EXCEPTION;
    e_alerta_duplicado  EXCEPTION;
  BEGIN
    -- 1. Valida se o item existe e recupera dono e nome
    BEGIN
      SELECT user_id, name INTO v_item_owner, v_item_name
      FROM items
      WHERE id = p_item_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE e_item_inexistente;
    END;

    -- 2. Valida o tipo do alerta
    IF p_type IS NULL OR p_type NOT IN ('lost', 'stolen') THEN
      RAISE e_tipo_invalido;
    END IF;

    -- 3. Impede alerta duplicado para o mesmo item
    SELECT COUNT(*) INTO v_alertas_ativos
    FROM alerts
    WHERE item_id = p_item_id
      AND status = 'active';

    IF v_alertas_ativos > 0 THEN
      RAISE e_alerta_duplicado;
    END IF;

    -- 4. Cria o alerta
    INSERT INTO alerts (
      item_id, type, last_seen_lat, last_seen_lng,
      last_seen_address, incident_date, description, status
    ) VALUES (
      p_item_id, p_type, p_last_seen_lat, p_last_seen_lng,
      p_last_seen_addr, p_incident_date, p_description, 'active'
    )
    RETURNING id INTO p_alert_id;

    -- 5. Atualiza o status do item
    UPDATE items
    SET status = p_type
    WHERE id = p_item_id;

    -- 6. Notifica o dono do item
    IF v_item_owner IS NOT NULL THEN
      INSERT INTO notifications (user_id, title, message, is_read)
      VALUES (
        v_item_owner,
        'Alerta registrado',
        'Seu item "' || v_item_name || '" foi marcado como ' ||
        CASE p_type WHEN 'lost' THEN 'perdido' ELSE 'furtado' END ||
        '. Alerta #' || p_alert_id || ' criado com sucesso.',
        0
      );
    END IF;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Alerta #' || p_alert_id || ' criado para o item "' || v_item_name || '".');

  EXCEPTION
    WHEN e_item_inexistente THEN
      RAISE_APPLICATION_ERROR(c_err_item_inexistente, 'Item id=' || p_item_id || ' nao encontrado.');
    WHEN e_tipo_invalido THEN
      RAISE_APPLICATION_ERROR(c_err_tipo_invalido, 'Tipo de alerta invalido: "' || p_type || '". Use ''lost'' ou ''stolen''.');
    WHEN e_alerta_duplicado THEN
      RAISE_APPLICATION_ERROR(c_err_alerta_duplicado, 'Ja existe um alerta ativo para o item id=' || p_item_id || '.');
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE_APPLICATION_ERROR(-20099, 'Erro inesperado em prc_registrar_alerta: ' || SQLERRM);
  END prc_registrar_alerta;


  PROCEDURE prc_encerrar_alerta(
    p_alert_id    IN alerts.id%TYPE,
    p_novo_status IN alerts.status%TYPE DEFAULT 'resolved'
  ) IS
    v_status_atual alerts.status%TYPE;
  BEGIN
    -- 1. Valida o status de destino
    IF p_novo_status IS NULL OR p_novo_status NOT IN ('resolved', 'canceled') THEN
      RAISE_APPLICATION_ERROR(c_err_status_invalido,
        'Status invalido: "' || p_novo_status || '". Use ''resolved'' ou ''canceled''.');
    END IF;

    -- 2. Busca o alerta com bloqueio da linha, evitando encerramento concorrente
    BEGIN
      SELECT status INTO v_status_atual
      FROM alerts
      WHERE id = p_alert_id
      FOR UPDATE;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(c_err_alerta_inexistente, 'Alerta id=' || p_alert_id || ' nao encontrado.');
    END;

    -- 3. So alertas ativos podem ser encerrados
    IF v_status_atual <> 'active' THEN
      ROLLBACK;
      RAISE_APPLICATION_ERROR(c_err_alerta_encerrado,
        'Alerta id=' || p_alert_id || ' ja esta com status "' || v_status_atual || '".');
    END IF;

    -- 4. Encerra o alerta. As triggers do script 07 registram a auditoria,
    --    devolvem o item ao status 'active' e notificam o dono.
    UPDATE alerts
    SET status = p_novo_status
    WHERE id = p_alert_id;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Alerta #' || p_alert_id || ' encerrado como "' || p_novo_status || '".');
  END prc_encerrar_alerta;

END pkg_biptag_alertas;
/


--------------------------------------------------------------------------------
-- PACKAGE 2: PKG_BIPTAG_RELATORIOS (especificacao)
-- Indicadores, resumos e consultas flexiveis usadas por relatorios, pelo
-- painel empresarial e pela API.
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_biptag_relatorios AS

  c_err_ordenacao_invalida CONSTANT PLS_INTEGER := -20010;
  c_err_tabela_invalida    CONSTANT PLS_INTEGER := -20011;
  c_err_usuario_inexistente CONSTANT PLS_INTEGER := -20004;

  -- Percentual de alertas do usuario que terminaram em devolucao concluida.
  FUNCTION fn_taxa_recuperacao_usuario(
    p_user_id IN app_users.id%TYPE
  ) RETURN NUMBER;

  -- Texto legivel com nome, categoria, status, ultimo alerta e ultima devolucao.
  FUNCTION fn_resumo_item_formatado(
    p_item_id IN items.id%TYPE
  ) RETURN VARCHAR2;

  -- Relatorio linha a linha dos itens de um usuario (CURSOR + LOOP + IF).
  PROCEDURE prc_relatorio_usuario(
    p_user_id IN app_users.id%TYPE
  );

  -- SQL dinamico: busca de itens com filtros opcionais e ordenacao escolhida
  -- em tempo de execucao. Filtros nulos sao ignorados.
  -- p_ordenar_por aceita: CRIACAO, NOME, CATEGORIA, STATUS.
  PROCEDURE prc_buscar_itens(
    p_categoria_id IN  items.category%TYPE DEFAULT NULL,
    p_status       IN  VARCHAR2            DEFAULT NULL,
    p_user_id      IN  items.user_id%TYPE  DEFAULT NULL,
    p_termo        IN  VARCHAR2            DEFAULT NULL,
    p_ordenar_por  IN  VARCHAR2            DEFAULT 'CRIACAO',
    p_resultado    OUT SYS_REFCURSOR
  );

  -- SQL dinamico: conta registros de uma tabela monitorada, opcionalmente
  -- filtrando por status. Tabelas aceitas: ITEMS, ALERTS, RETURN_PROCESSES,
  -- COMPANY_EMPLOYEES.
  FUNCTION fn_contar_por_status(
    p_tabela IN VARCHAR2,
    p_status IN VARCHAR2 DEFAULT NULL
  ) RETURN NUMBER;

  -- SQL dinamico: imprime a distribuicao por status de todas as tabelas
  -- monitoradas, como um painel de indicadores em tempo real.
  PROCEDURE prc_painel_status;

  -- Devolve o ultimo comando gerado por prc_buscar_itens nesta sessao
  -- (util para auditoria e para demonstrar o SQL montado).
  FUNCTION fn_ultimo_sql RETURN VARCHAR2;

END pkg_biptag_relatorios;
/

--------------------------------------------------------------------------------
-- PACKAGE 2: PKG_BIPTAG_RELATORIOS (corpo)
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY pkg_biptag_relatorios AS

  -- Variavel de sessao com o ultimo SQL dinamico montado
  g_ultimo_sql VARCHAR2(4000);

  -- Valida o nome da tabela contra uma lista fechada (protege contra SQL
  -- injection, ja que nomes de tabela nao podem ser passados como bind).
  FUNCTION fn_tabela_monitorada(p_tabela IN VARCHAR2) RETURN VARCHAR2 IS
    v_tabela VARCHAR2(128) := UPPER(TRIM(p_tabela));
  BEGIN
    IF v_tabela IS NULL
       OR v_tabela NOT IN ('ITEMS', 'ALERTS', 'RETURN_PROCESSES', 'COMPANY_EMPLOYEES') THEN
      RAISE_APPLICATION_ERROR(c_err_tabela_invalida,
        'Tabela "' || p_tabela || '" nao e monitorada. Use ITEMS, ALERTS, RETURN_PROCESSES ou COMPANY_EMPLOYEES.');
    END IF;
    RETURN DBMS_ASSERT.SIMPLE_SQL_NAME(v_tabela);
  END fn_tabela_monitorada;


  FUNCTION fn_taxa_recuperacao_usuario(
    p_user_id IN app_users.id%TYPE
  ) RETURN NUMBER IS
    v_total_alertas    NUMBER := 0;
    v_total_concluidos NUMBER := 0;
    v_existe_usuario   NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO v_existe_usuario
    FROM app_users
    WHERE id = p_user_id;

    IF v_existe_usuario = 0 THEN
      RETURN NULL;
    END IF;

    SELECT COUNT(*) INTO v_total_alertas
    FROM alerts a
    JOIN items i ON i.id = a.item_id
    WHERE i.user_id = p_user_id;

    IF v_total_alertas = 0 THEN
      RETURN 0;
    END IF;

    SELECT COUNT(*) INTO v_total_concluidos
    FROM alerts a
    JOIN items i ON i.id = a.item_id
    JOIN return_processes rp ON rp.alert_id = a.id
    WHERE i.user_id = p_user_id
      AND rp.status = 'completed';

    RETURN ROUND((v_total_concluidos / v_total_alertas) * 100, 2);

  EXCEPTION
    WHEN ZERO_DIVIDE THEN
      RETURN 0;
    WHEN NO_DATA_FOUND THEN
      RETURN NULL;
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Erro em fn_taxa_recuperacao_usuario: ' || SQLERRM);
      RETURN NULL;
  END fn_taxa_recuperacao_usuario;


  FUNCTION fn_resumo_item_formatado(
    p_item_id IN items.id%TYPE
  ) RETURN VARCHAR2 IS
    v_item_name     items.name%TYPE;
    v_category_name category.name%TYPE;
    v_item_status   items.status%TYPE;
    v_alert_type    alerts.type%TYPE;
    v_alert_status  alerts.status%TYPE;
    v_return_status return_processes.status%TYPE;
    v_partner_name  partner_points.name%TYPE;
    v_resumo        VARCHAR2(4000);
  BEGIN
    SELECT i.name, c.name, NVL(i.status, 'sem status')
    INTO v_item_name, v_category_name, v_item_status
    FROM items i
    JOIN category c ON c.id = i.category
    WHERE i.id = p_item_id;

    v_resumo := v_item_name || ' | Categoria: ' || v_category_name
                || ' | Status: ' || UPPER(v_item_status);

    BEGIN
      SELECT type, status
      INTO v_alert_type, v_alert_status
      FROM (
        SELECT type, status
        FROM alerts
        WHERE item_id = p_item_id
        ORDER BY created_at DESC, id DESC
      )
      WHERE ROWNUM = 1;

      v_resumo := v_resumo || ' | Alerta: ' || UPPER(v_alert_type)
                  || ' (' || v_alert_status || ')';
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        NULL;
    END;

    BEGIN
      SELECT rp.status, pp.name
      INTO v_return_status, v_partner_name
      FROM (
        SELECT rp.status, rp.partner_point_id, rp.created_at
        FROM return_processes rp
        JOIN alerts a ON a.id = rp.alert_id
        WHERE a.item_id = p_item_id
        ORDER BY rp.created_at DESC
      ) rp
      LEFT JOIN partner_points pp ON pp.id = rp.partner_point_id
      WHERE ROWNUM = 1;

      v_resumo := v_resumo || ' | Devolução: ' || UPPER(v_return_status)
                  || CASE WHEN v_partner_name IS NOT NULL
                          THEN ' em ' || v_partner_name
                          ELSE '' END;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        NULL;
    END;

    RETURN v_resumo;

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN 'ITEM NAO ENCONTRADO';
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Erro em fn_resumo_item_formatado: ' || SQLERRM);
      RETURN 'ERRO AO GERAR RESUMO';
  END fn_resumo_item_formatado;


  PROCEDURE prc_relatorio_usuario(
    p_user_id IN app_users.id%TYPE
  ) IS
    CURSOR c_itens_usuario IS
      SELECT i.id AS item_id, i.name AS item_name, i.status AS item_status
      FROM items i
      WHERE i.user_id = p_user_id
      ORDER BY i.id;

    v_nome_usuario         app_users.full_name%TYPE;
    v_existe_usuario       NUMBER;
    v_total_itens          NUMBER := 0;
    v_total_alertas_ativos NUMBER := 0;
    v_total_devolvidos     NUMBER := 0;
    v_linha_status         VARCHAR2(200);

    v_ultimo_alerta_id     alerts.id%TYPE;
    v_ultimo_alerta_tipo   alerts.type%TYPE;
    v_ultimo_alerta_status alerts.status%TYPE;
    v_ultima_devolucao     return_processes.status%TYPE;
  BEGIN
    SELECT COUNT(*), MAX(full_name)
    INTO v_existe_usuario, v_nome_usuario
    FROM app_users
    WHERE id = p_user_id;

    IF v_existe_usuario = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_usuario_inexistente, 'Usuario id=' || p_user_id || ' nao encontrado.');
    END IF;

    DBMS_OUTPUT.PUT_LINE('=================================================');
    DBMS_OUTPUT.PUT_LINE('RELATORIO DE ITENS - Usuario: ' || v_nome_usuario);
    DBMS_OUTPUT.PUT_LINE('=================================================');

    FOR r_item IN c_itens_usuario LOOP
      v_total_itens          := v_total_itens + 1;
      v_ultimo_alerta_id     := NULL;
      v_ultimo_alerta_tipo   := NULL;
      v_ultimo_alerta_status := NULL;
      v_ultima_devolucao     := NULL;

      BEGIN
        SELECT id, type, status
        INTO v_ultimo_alerta_id, v_ultimo_alerta_tipo, v_ultimo_alerta_status
        FROM (
          SELECT id, type, status
          FROM alerts
          WHERE item_id = r_item.item_id
          ORDER BY created_at DESC, id DESC
        )
        WHERE ROWNUM = 1;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          NULL;
      END;

      IF v_ultimo_alerta_id IS NOT NULL THEN
        BEGIN
          SELECT status
          INTO v_ultima_devolucao
          FROM (
            SELECT status
            FROM return_processes
            WHERE alert_id = v_ultimo_alerta_id
            ORDER BY created_at DESC
          )
          WHERE ROWNUM = 1;
        EXCEPTION
          WHEN NO_DATA_FOUND THEN
            NULL;
        END;
      END IF;

      IF v_ultima_devolucao = 'completed' THEN
        v_linha_status     := 'DEVOLVIDO COM SUCESSO';
        v_total_devolvidos := v_total_devolvidos + 1;
      ELSIF v_ultimo_alerta_status = 'active' THEN
        v_linha_status         := 'ALERTA ATIVO (' || UPPER(v_ultimo_alerta_tipo) || ')';
        v_total_alertas_ativos := v_total_alertas_ativos + 1;
      ELSIF v_ultimo_alerta_status IS NULL THEN
        v_linha_status := 'SEM OCORRENCIAS';
      ELSE
        v_linha_status := 'ALERTA ' || UPPER(v_ultimo_alerta_status);
      END IF;

      DBMS_OUTPUT.PUT_LINE('Item #' || r_item.item_id || ' - ' || r_item.item_name ||
                           ' | Status: ' || v_linha_status);
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('-------------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('Total de itens: ' || v_total_itens);
    DBMS_OUTPUT.PUT_LINE('Alertas ativos: ' || v_total_alertas_ativos);
    DBMS_OUTPUT.PUT_LINE('Itens devolvidos: ' || v_total_devolvidos);
    DBMS_OUTPUT.PUT_LINE('=================================================');
  END prc_relatorio_usuario;


  PROCEDURE prc_buscar_itens(
    p_categoria_id IN  items.category%TYPE DEFAULT NULL,
    p_status       IN  VARCHAR2            DEFAULT NULL,
    p_user_id      IN  items.user_id%TYPE  DEFAULT NULL,
    p_termo        IN  VARCHAR2            DEFAULT NULL,
    p_ordenar_por  IN  VARCHAR2            DEFAULT 'CRIACAO',
    p_resultado    OUT SYS_REFCURSOR
  ) IS
    v_sql   VARCHAR2(4000);
    v_ordem VARCHAR2(100);
  BEGIN
    v_sql := 'SELECT i.id, i.name, c.name AS categoria, i.status, i.tag_id, i.user_id, i.created_at '
          || 'FROM items i JOIN category c ON c.id = i.category WHERE 1 = 1';

    -- Cada filtro so entra no WHERE quando foi informado. Quando nao foi,
    -- o placeholder continua presente em uma condicao sempre verdadeira,
    -- para que a lista de binds do USING seja sempre a mesma.
    IF p_categoria_id IS NOT NULL THEN
      v_sql := v_sql || ' AND i.category = :b_categoria';
    ELSE
      v_sql := v_sql || ' AND (1 = 1 OR :b_categoria IS NULL)';
    END IF;

    IF p_status IS NOT NULL THEN
      v_sql := v_sql || ' AND UPPER(i.status) = UPPER(:b_status)';
    ELSE
      v_sql := v_sql || ' AND (1 = 1 OR :b_status IS NULL)';
    END IF;

    IF p_user_id IS NOT NULL THEN
      v_sql := v_sql || ' AND i.user_id = :b_usuario';
    ELSE
      v_sql := v_sql || ' AND (1 = 1 OR :b_usuario IS NULL)';
    END IF;

    IF p_termo IS NOT NULL THEN
      v_sql := v_sql || ' AND (UPPER(i.name) LIKE ''%'' || UPPER(:b_termo) || ''%'''
                     || ' OR UPPER(DBMS_LOB.SUBSTR(i.description, 4000, 1)) LIKE ''%'' || UPPER(:b_termo2) || ''%'')';
    ELSE
      v_sql := v_sql || ' AND (1 = 1 OR :b_termo IS NULL OR :b_termo2 IS NULL)';
    END IF;

    -- A ordenacao nao pode ser bind; por isso vem de uma lista fechada
    v_ordem := CASE UPPER(NVL(TRIM(p_ordenar_por), 'CRIACAO'))
                 WHEN 'CRIACAO'   THEN 'i.created_at DESC, i.id DESC'
                 WHEN 'NOME'      THEN 'i.name, i.id'
                 WHEN 'CATEGORIA' THEN 'c.name, i.name'
                 WHEN 'STATUS'    THEN 'i.status, i.name'
                 ELSE NULL
               END;

    IF v_ordem IS NULL THEN
      RAISE_APPLICATION_ERROR(c_err_ordenacao_invalida,
        'Ordenacao "' || p_ordenar_por || '" invalida. Use CRIACAO, NOME, CATEGORIA ou STATUS.');
    END IF;

    v_sql := v_sql || ' ORDER BY ' || v_ordem;
    g_ultimo_sql := v_sql;

    OPEN p_resultado FOR v_sql
      USING p_categoria_id, p_status, p_user_id, p_termo, p_termo;
  END prc_buscar_itens;


  FUNCTION fn_contar_por_status(
    p_tabela IN VARCHAR2,
    p_status IN VARCHAR2 DEFAULT NULL
  ) RETURN NUMBER IS
    v_tabela VARCHAR2(128);
    v_sql    VARCHAR2(500);
    v_total  NUMBER;
  BEGIN
    v_tabela := fn_tabela_monitorada(p_tabela);
    v_sql    := 'SELECT COUNT(*) FROM ' || v_tabela;

    IF p_status IS NOT NULL THEN
      v_sql := v_sql || ' WHERE UPPER(status) = UPPER(:b_status)';
      EXECUTE IMMEDIATE v_sql INTO v_total USING p_status;
    ELSE
      EXECUTE IMMEDIATE v_sql INTO v_total;
    END IF;

    RETURN v_total;
  END fn_contar_por_status;


  PROCEDURE prc_painel_status IS
    TYPE t_tabelas IS TABLE OF VARCHAR2(30);
    v_tabelas t_tabelas := t_tabelas('ITEMS', 'ALERTS', 'RETURN_PROCESSES', 'COMPANY_EMPLOYEES');
    v_cursor  SYS_REFCURSOR;
    v_status  VARCHAR2(4000);
    v_total   NUMBER;
  BEGIN
    DBMS_OUTPUT.PUT_LINE('================ PAINEL DE STATUS ================');
    FOR i IN 1 .. v_tabelas.COUNT LOOP
      DBMS_OUTPUT.PUT_LINE(v_tabelas(i) || ' (total: ' || fn_contar_por_status(v_tabelas(i)) || ')');

      OPEN v_cursor FOR
        'SELECT NVL(status, ''(sem status)''), COUNT(*) FROM '
        || fn_tabela_monitorada(v_tabelas(i))
        || ' GROUP BY status ORDER BY 2 DESC';
      LOOP
        FETCH v_cursor INTO v_status, v_total;
        EXIT WHEN v_cursor%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE('   ' || RPAD(v_status, 20) || v_total);
      END LOOP;
      CLOSE v_cursor;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('==================================================');
  EXCEPTION
    WHEN OTHERS THEN
      IF v_cursor%ISOPEN THEN
        CLOSE v_cursor;
      END IF;
      RAISE;
  END prc_painel_status;


  FUNCTION fn_ultimo_sql RETURN VARCHAR2 IS
  BEGIN
    RETURN g_ultimo_sql;
  END fn_ultimo_sql;

END pkg_biptag_relatorios;
/

--------------------------------------------------------------------------------
-- VERIFICACAO DE COMPILACAO
-- Lista os objetos dos packages e o status de cada um (esperado: VALID).
--------------------------------------------------------------------------------
SELECT object_name, object_type, status
FROM user_objects
WHERE object_name IN ('PKG_BIPTAG_ALERTAS', 'PKG_BIPTAG_RELATORIOS')
ORDER BY object_name, object_type;
