SET SERVEROUTPUT ON;

--------------------------------------------------------------------------------
-- 07_TRIGGERS.SQL  (Fase 7 - Consolidacao em Oracle PL/SQL)
--
-- Objetos criados:
--   ALERT_AUDIT_LOG            tabela de auditoria do ciclo de vida dos alertas
--   TRG_ALERTS_AUDITORIA       trigger de auditoria (INSERT, UPDATE, DELETE)
--   TRG_ALERTS_SINCRONIZA_ITEM trigger de automacao: ao encerrar um alerta,
--                              devolve o item ao status 'active' e avisa o dono
--
-- O script pode ser executado mais de uma vez: a criacao da tabela e do
-- indice ignora o erro de objeto existente, e as triggers usam OR REPLACE.
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- 1. TABELA DE AUDITORIA
--------------------------------------------------------------------------------
DECLARE
  e_objeto_existe EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_objeto_existe, -955);
BEGIN
  EXECUTE IMMEDIATE q'[
    CREATE TABLE alert_audit_log (
      id               NUMBER GENERATED ALWAYS AS IDENTITY NOT NULL,
      alert_id         NUMBER,
      item_id          NUMBER,
      operacao         VARCHAR2(10)  NOT NULL,
      tipo_alerta      VARCHAR2(20),
      status_anterior  VARCHAR2(20),
      status_novo      VARCHAR2(20),
      usuario_banco    VARCHAR2(128) DEFAULT SYS_CONTEXT('USERENV', 'SESSION_USER'),
      origem           VARCHAR2(200),
      data_evento      TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
      CONSTRAINT alert_audit_log_pkey PRIMARY KEY (id),
      CONSTRAINT alert_audit_log_op_chk CHECK (operacao IN ('INSERT', 'UPDATE', 'DELETE'))
    )]';
  DBMS_OUTPUT.PUT_LINE('Tabela ALERT_AUDIT_LOG criada.');
EXCEPTION
  WHEN e_objeto_existe THEN
    DBMS_OUTPUT.PUT_LINE('Tabela ALERT_AUDIT_LOG ja existe, mantida.');
END;
/

DECLARE
  e_objeto_existe EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_objeto_existe, -955);
BEGIN
  EXECUTE IMMEDIATE 'CREATE INDEX idx_alert_audit_log_alert_id ON alert_audit_log(alert_id)';
  DBMS_OUTPUT.PUT_LINE('Indice IDX_ALERT_AUDIT_LOG_ALERT_ID criado.');
EXCEPTION
  WHEN e_objeto_existe THEN
    DBMS_OUTPUT.PUT_LINE('Indice IDX_ALERT_AUDIT_LOG_ALERT_ID ja existe, mantido.');
END;
/


--------------------------------------------------------------------------------
-- 2. TRIGGER DE AUDITORIA: TRG_ALERTS_AUDITORIA
--
-- Finalidade:
--   Registra em ALERT_AUDIT_LOG toda criacao, alteracao e exclusao de alertas,
--   guardando o status anterior e o novo, o usuario do banco e a origem da
--   operacao (por exemplo, a API via JDBC ou uma ferramenta de SQL).
--
-- Valor para o sistema:
--   Cria uma trilha de auditoria que nao depende da aplicacao. Mesmo que um
--   alerta seja alterado direto no banco, o historico fica registrado, o que
--   sustenta o requisito de governanca e auditoria definido nas fases
--   anteriores (LGPD e auditoria de denuncias).
--------------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_alerts_auditoria
AFTER INSERT OR UPDATE OR DELETE ON alerts
FOR EACH ROW
DECLARE
  v_operacao VARCHAR2(10);
  v_origem   VARCHAR2(200);
BEGIN
  IF INSERTING THEN
    v_operacao := 'INSERT';
  ELSIF UPDATING THEN
    v_operacao := 'UPDATE';
  ELSE
    v_operacao := 'DELETE';
  END IF;

  v_origem := SUBSTR(
                NVL(SYS_CONTEXT('USERENV', 'MODULE'), 'desconhecido') || ' @ ' ||
                NVL(SYS_CONTEXT('USERENV', 'HOST'), 'host desconhecido'),
                1, 200);

  INSERT INTO alert_audit_log (
    alert_id, item_id, operacao, tipo_alerta, status_anterior, status_novo, origem
  ) VALUES (
    COALESCE(:NEW.id, :OLD.id),
    COALESCE(:NEW.item_id, :OLD.item_id),
    v_operacao,
    COALESCE(:NEW.type, :OLD.type),
    :OLD.status,
    :NEW.status,
    v_origem
  );
END trg_alerts_auditoria;
/


--------------------------------------------------------------------------------
-- 3. TRIGGER DE AUTOMACAO: TRG_ALERTS_SINCRONIZA_ITEM
--
-- Finalidade:
--   Quando um alerta passa de 'active' para 'resolved' ou 'canceled', o item
--   vinculado volta ao status 'active' (se ainda estiver como 'lost' ou
--   'stolen') e o dono recebe uma notificacao automatica.
--
-- Valor para o sistema:
--   Garante a consistencia entre alerta e item em qualquer caminho de
--   encerramento (API, painel empresarial ou package), sem depender de cada
--   ponto da aplicacao lembrar de atualizar o item. A condicao sobre o status
--   do item preserva estados definidos pela API, como 'safe' apos a devolucao.
--------------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_alerts_sincroniza_item
AFTER UPDATE OF status ON alerts
FOR EACH ROW
WHEN (OLD.status = 'active' AND NEW.status IN ('resolved', 'canceled'))
DECLARE
  v_dono      items.user_id%TYPE;
  v_nome_item items.name%TYPE;
BEGIN
  UPDATE items
  SET status = 'active'
  WHERE id = :NEW.item_id
    AND LOWER(status) IN ('lost', 'stolen');

  BEGIN
    SELECT user_id, name INTO v_dono, v_nome_item
    FROM items
    WHERE id = :NEW.item_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      v_dono := NULL;
  END;

  IF v_dono IS NOT NULL THEN
    INSERT INTO notifications (user_id, title, message, is_read)
    VALUES (
      v_dono,
      'Alerta encerrado',
      'O alerta #' || :NEW.id || ' do item "' || v_nome_item || '" foi ' ||
      CASE :NEW.status WHEN 'resolved' THEN 'resolvido' ELSE 'cancelado' END || '.',
      0
    );
  END IF;
END trg_alerts_sincroniza_item;
/

--------------------------------------------------------------------------------
-- VERIFICACAO DE COMPILACAO
--------------------------------------------------------------------------------
SELECT trigger_name, triggering_event, table_name, status
FROM user_triggers
WHERE trigger_name IN ('TRG_ALERTS_AUDITORIA', 'TRG_ALERTS_SINCRONIZA_ITEM')
ORDER BY trigger_name;
