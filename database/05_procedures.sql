SET SERVEROUTPUT ON;

--------------------------------------------------------------------------------
-- PROCEDURE 1: PRC_REGISTRAR_ALERTA
--
-- Proposito:
--   Registra um novo alerta (perda ou furto) para um item e, na mesma
--   transacao, cria automaticamente uma notificacao para o dono do item.
--   Equivale, no dominio do projeto, a "gerar um alerta a partir de um
--   evento critico" (aqui, o evento critico e' o usuario reportando que
--   perdeu ou teve o item furtado).
--
--   Pensada para ser chamada pelo backend Java assim que o usuario
--   confirma, no app mobile, que um item foi perdido/furtado
--   (fluxo: App -> API Java -> JDBC -> esta procedure).
--
-- Parametros:
--   p_item_id        (IN)  - item que sofreu o incidente
--   p_type            (IN)  - 'lost' ou 'stolen'
--   p_incident_date   (IN)  - data do incidente (texto, mesmo formato da
--                              coluna original alerts.incident_date)
--   p_last_seen_lat   (IN)  - latitude do ultimo local visto (opcional)
--   p_last_seen_lng   (IN)  - longitude do ultimo local visto (opcional)
--   p_last_seen_addr  (IN)  - endereco do ultimo local visto (opcional)
--   p_description     (IN)  - descricao livre do ocorrido (opcional)
--   p_alert_id        (OUT) - id do alerta recem-criado, devolvido para
--                              quem chamou (o backend Java usa esse id
--                              para redirecionar o usuario na tela)
--
-- Regras de negocio implementadas:
--   - Valida se o item existe antes de criar o alerta (senao lanca erro)
--   - Valida se o tipo informado e' 'lost' ou 'stolen' (mesma regra do
--     CHECK da tabela, validada aqui tambem para dar uma mensagem clara)
--   - Impede duplicidade: se o item ja tem um alerta ATIVO, nao cria outro
--   - Atualiza o status do item para refletir o alerta criado
--   - Cria uma notificacao automatica para o dono do item
--
-- Boas praticas aplicadas:
--   - Parametros IN e OUT
--   - IF para validacoes de negocio
--   - Tratamento de excecoes especificas (uma delas definida pelo usuario,
--     com RAISE_APPLICATION_ERROR) e generica (OTHERS)
--   - COMMIT apenas no final, apos todas as operacoes terem sucesso
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE prc_registrar_alerta(
  p_item_id         IN  items.id%TYPE,
  p_type            IN  alerts.type%TYPE,
  p_incident_date   IN  alerts.incident_date%TYPE,
  p_last_seen_lat   IN  alerts.last_seen_lat%TYPE DEFAULT NULL,
  p_last_seen_lng   IN  alerts.last_seen_lng%TYPE DEFAULT NULL,
  p_last_seen_addr  IN  alerts.last_seen_address%TYPE DEFAULT NULL,
  p_description     IN  alerts.description%TYPE DEFAULT NULL,
  p_alert_id        OUT alerts.id%TYPE
)
IS
  v_item_owner        app_users.id%TYPE;
  v_item_name         items.name%TYPE;
  v_alertas_ativos    NUMBER;

  e_item_inexistente   EXCEPTION;
  e_tipo_invalido       EXCEPTION;
  e_alerta_duplicado    EXCEPTION;

BEGIN
  -- 1. Valida se o item existe e recupera dono/nome
  BEGIN
    SELECT user_id, name INTO v_item_owner, v_item_name
    FROM items
    WHERE id = p_item_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE e_item_inexistente;
  END;

  -- 2. Valida o tipo do alerta
  IF p_type NOT IN ('lost', 'stolen') THEN
    RAISE e_tipo_invalido;
  END IF;

  -- 3. Verifica se ja existe alerta ativo para este item (evita duplicidade)
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

  -- 5. Atualiza o status do item para refletir o incidente
  UPDATE items
  SET status = p_type
  WHERE id = p_item_id;

  -- 6. Cria notificacao automatica para o dono do item
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
    RAISE_APPLICATION_ERROR(-20001, 'Item id=' || p_item_id || ' nao encontrado.');
  WHEN e_tipo_invalido THEN
    RAISE_APPLICATION_ERROR(-20002, 'Tipo de alerta invalido: "' || p_type || '". Use ''lost'' ou ''stolen''.');
  WHEN e_alerta_duplicado THEN
    RAISE_APPLICATION_ERROR(-20003, 'Ja existe um alerta ativo para o item id=' || p_item_id || '.');
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE_APPLICATION_ERROR(-20099, 'Erro inesperado em prc_registrar_alerta: ' || SQLERRM);
END prc_registrar_alerta;
/

--------------------------------------------------------------------------------
-- PROCEDURE 2: PRC_RELATORIO_USUARIO
--
-- Proposito:
--   Gera um relatorio resumido, linha a linha (via CURSOR), de todos os
--   itens de um usuario, com seus alertas e status de devolucao,
--   imprimindo o resultado formatado com DBMS_OUTPUT. Simula uma rotina
--   de backend que roda periodicamente (ex: job noturno) ou que e'
--   chamada sob demanda pela API Java para montar uma tela de "meus itens".
--
-- Parametros:
--   p_user_id (IN) - id do usuario para o qual o relatorio sera gerado
--
-- Regras implementadas:
--   - Usa CURSOR explicito para percorrer os itens do usuario
--   - Usa LOOP para iterar linha a linha
--   - Para cada item, usa IF para decidir a mensagem de status
--   - Conta totais (itens, alertas ativos, devolucoes concluidas) durante
--     o loop e imprime um resumo final
--
-- Boas praticas aplicadas:
--   - CURSOR + LOOP + IF, conforme pedido no enunciado
--   - Tratamento de excecao para usuario inexistente e generica (OTHERS)
--   - Comentarios explicando cada trecho
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE prc_relatorio_usuario(
  p_user_id IN app_users.id%TYPE
)
IS
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

  e_usuario_inexistente EXCEPTION;

BEGIN
  SELECT COUNT(*), MAX(full_name)
  INTO v_existe_usuario, v_nome_usuario
  FROM app_users
  WHERE id = p_user_id;

  IF v_existe_usuario = 0 THEN
    RAISE e_usuario_inexistente;
  END IF;

  DBMS_OUTPUT.PUT_LINE('=================================================');
  DBMS_OUTPUT.PUT_LINE('RELATORIO DE ITENS - Usuario: ' || v_nome_usuario);
  DBMS_OUTPUT.PUT_LINE('=================================================');

  -- percorre cada item do usuario
  FOR r_item IN c_itens_usuario LOOP
    v_total_itens := v_total_itens + 1;

    v_ultimo_alerta_id := NULL;
    v_ultimo_alerta_tipo := NULL;
    v_ultimo_alerta_status := NULL;
    v_ultima_devolucao := NULL;

    -- busca o alerta mais recente deste item, se existir
    BEGIN
      SELECT id, type, status
      INTO v_ultimo_alerta_id, v_ultimo_alerta_tipo, v_ultimo_alerta_status
      FROM (
        SELECT id, type, status
        FROM alerts
        WHERE item_id = r_item.item_id
        ORDER BY created_at DESC
      )
      WHERE ROWNUM = 1;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        NULL;
    END;

    -- se houver alerta, busca a devolucao mais recente ligada a ele
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
      v_linha_status := 'DEVOLVIDO COM SUCESSO';
      v_total_devolvidos := v_total_devolvidos + 1;
    ELSIF v_ultimo_alerta_status = 'active' THEN
      v_linha_status := 'ALERTA ATIVO (' || UPPER(v_ultimo_alerta_tipo) || ')';
      v_total_alertas_ativos := v_total_alertas_ativos + 1;
    ELSIF v_ultimo_alerta_status IS NULL THEN
      v_linha_status := 'SEM OCORRENCIAS';
    ELSE
      v_linha_status := 'ALERTA ' || UPPER(v_ultimo_alerta_status);
    END IF;

    DBMS_OUTPUT.PUT_LINE(
      'Item #' || r_item.item_id || ' - ' || r_item.item_name ||
      ' | Status: ' || v_linha_status
    );
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('-------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Total de itens: ' || v_total_itens);
  DBMS_OUTPUT.PUT_LINE('Alertas ativos: ' || v_total_alertas_ativos);
  DBMS_OUTPUT.PUT_LINE('Itens devolvidos: ' || v_total_devolvidos);
  DBMS_OUTPUT.PUT_LINE('=================================================');

EXCEPTION
  WHEN e_usuario_inexistente THEN
    RAISE_APPLICATION_ERROR(-20004, 'Usuario id=' || p_user_id || ' nao encontrado.');
  WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20099, 'Erro inesperado em prc_relatorio_usuario: ' || SQLERRM);
END prc_relatorio_usuario;
/

--------------------------------------------------------------------------------
-- EXEMPLOS DE USO DAS PROCEDURES
--------------------------------------------------------------------------------

-- Uso 1: registrar um novo alerta para o item #3 (chaves), simulando o
-- usuario reportando perda pelo app
DECLARE
  v_novo_alerta_id alerts.id%TYPE;
BEGIN
  prc_registrar_alerta(
    p_item_id        => 3,
    p_type            => 'lost',
    p_incident_date   => '2026-09-20',
    p_last_seen_lat   => -16.6799,
    p_last_seen_lng   => -49.2550,
    p_last_seen_addr  => 'Rua 10, Centro, Goiânia - GO',
    p_description     => 'Esqueci as chaves na mesa de um restaurante',
    p_alert_id        => v_novo_alerta_id
  );
  DBMS_OUTPUT.PUT_LINE('ID do alerta criado: ' || v_novo_alerta_id);
END;
/

-- Uso 2: tentar registrar alerta duplicado para o mesmo item
DECLARE
  v_novo_alerta_id alerts.id%TYPE;
BEGIN
  prc_registrar_alerta(
    p_item_id        => 3,
    p_type            => 'lost',
    p_incident_date   => '2026-09-21',
    p_alert_id        => v_novo_alerta_id
  );
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Erro esperado: ' || SQLERRM);
END;
/

-- Uso 3: gerar o relatorio de itens de um usuario
BEGIN
  prc_relatorio_usuario('11111111-1111-1111-1111-111111111111');
END;
/

-- Uso 4: relatorio de usuario com item ja devolvido (Maria Souza)
BEGIN
  prc_relatorio_usuario('22222222-2222-2222-2222-222222222222');
END;
/
