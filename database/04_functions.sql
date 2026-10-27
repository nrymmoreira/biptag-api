SET SERVEROUTPUT ON;

--------------------------------------------------------------------------------
-- FUNCTION 1: FN_TAXA_RECUPERACAO_USUARIO
--
-- Proposito:
--   Calcula o indicador de "taxa de recuperacao" de um usuario: entre todos
--   os alertas (perda/furto) que ele abriu, qual percentual chegou a um
--   processo de devolucao concluido (return_processes.status = 'completed').
--
-- Parametros:
--   p_user_id (IN) - id (uuid/varchar2) do usuario dono dos itens
--
-- Retorno:
--   NUMBER - percentual de 0 a 100, com 2 casas decimais.
--            Retorna NULL se o usuario nao existir.
--            Retorna 0 se o usuario existir mas nunca teve alerta.
--
-- Boas praticas aplicadas:
--   - Parametro IN tipado com %TYPE (acompanha a coluna da tabela)
--   - Tratamento de excecoes (NO_DATA_FOUND, ZERO_DIVIDE, OTHERS)
--   - Comentarios explicando cada bloco
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_taxa_recuperacao_usuario(
  p_user_id IN app_users.id%TYPE
) RETURN NUMBER
IS
  v_total_alertas     NUMBER := 0;
  v_total_concluidos  NUMBER := 0;
  v_taxa              NUMBER;
  v_existe_usuario    NUMBER := 0;
BEGIN
  -- Valida se o usuario existe antes de calcular qualquer coisa
  SELECT COUNT(*) INTO v_existe_usuario
  FROM app_users
  WHERE id = p_user_id;

  IF v_existe_usuario = 0 THEN
    RETURN NULL; -- usuario inexistente
  END IF;

  -- Conta o total de alertas abertos pelos itens desse usuario
  SELECT COUNT(*)
  INTO v_total_alertas
  FROM alerts a
  JOIN items i ON i.id = a.item_id
  WHERE i.user_id = p_user_id;

  -- Se nunca abriu alerta, taxa e' 0 (nao ha o que dividir)
  IF v_total_alertas = 0 THEN
    RETURN 0;
  END IF;

  -- Conta quantos desses alertas geraram devolucao concluida
  SELECT COUNT(*)
  INTO v_total_concluidos
  FROM alerts a
  JOIN items i ON i.id = a.item_id
  JOIN return_processes rp ON rp.alert_id = a.id
  WHERE i.user_id = p_user_id
    AND rp.status = 'completed';

  v_taxa := ROUND((v_total_concluidos / v_total_alertas) * 100, 2);

  RETURN v_taxa;

EXCEPTION
  WHEN ZERO_DIVIDE THEN
    RETURN 0;
  WHEN NO_DATA_FOUND THEN
    RETURN NULL;
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Erro em fn_taxa_recuperacao_usuario: ' || SQLERRM);
    RETURN NULL;
END fn_taxa_recuperacao_usuario;
/

--------------------------------------------------------------------------------
-- FUNCTION 2: FN_RESUMO_ITEM_FORMATADO
--
-- Proposito:
--   Retorna uma string formatada e legivel com o resumo do status de um
--   item: nome, categoria, status atual e, se houver, informacoes do
--   alerta e da devolucao associados. Util para exibir em telas de
--   listagem, notificacoes ou logs, sem o backend precisar montar a
--   string manualmente a partir de varias colunas.
--
-- Parametros:
--   p_item_id (IN) - id do item
--
-- Retorno:
--   VARCHAR2 - texto formatado, por exemplo:
--     "iPhone 14 Pro | Categoria: Eletrônicos | Status: PERDIDO (alerta ativo)
--      | Aguardando devolução em Loja Parceira Centro"
--   Retorna 'ITEM NAO ENCONTRADO' se o id nao existir.
--
-- Boas praticas aplicadas:
--   - Parametro IN tipado com %TYPE
--   - Uso de cursor implicito + tratamento de NO_DATA_FOUND
--   - Concatenacao defensiva (NVL) para campos que podem ser nulos
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_resumo_item_formatado(
  p_item_id IN items.id%TYPE
) RETURN VARCHAR2
IS
  v_item_name       items.name%TYPE;
  v_category_name   category.name%TYPE;
  v_item_status     items.status%TYPE;
  v_alert_type      alerts.type%TYPE;
  v_alert_status    alerts.status%TYPE;
  v_return_status   return_processes.status%TYPE;
  v_partner_name    partner_points.name%TYPE;
  v_resumo          VARCHAR2(4000);
BEGIN
  -- Dados basicos do item + categoria
  SELECT i.name, c.name, NVL(i.status, 'sem status')
  INTO v_item_name, v_category_name, v_item_status
  FROM items i
  JOIN category c ON c.id = i.category
  WHERE i.id = p_item_id;

  v_resumo := v_item_name || ' | Categoria: ' || v_category_name
              || ' | Status: ' || UPPER(v_item_status);

  -- Busca o alerta mais recente do item, se existir (pode nao haver nenhum)
  BEGIN
    SELECT type, status
    INTO v_alert_type, v_alert_status
    FROM (
      SELECT type, status
      FROM alerts
      WHERE item_id = p_item_id
      ORDER BY created_at DESC
    )
    WHERE ROWNUM = 1;

    v_resumo := v_resumo || ' | Alerta: ' || UPPER(v_alert_type)
                || ' (' || v_alert_status || ')';
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      NULL; -- item nunca teve alerta, segue sem essa parte do texto
  END;

  -- Busca o processo de devolucao mais recente ligado a esse item, se houver
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
      NULL; -- item ainda nao entrou em processo de devolucao
  END;

  RETURN v_resumo;

EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RETURN 'ITEM NAO ENCONTRADO';
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Erro em fn_resumo_item_formatado: ' || SQLERRM);
    RETURN 'ERRO AO GERAR RESUMO';
END fn_resumo_item_formatado;
/

--------------------------------------------------------------------------------
-- EXEMPLOS DE USO DAS FUNCTIONS EM CONSULTAS SQL
--------------------------------------------------------------------------------

-- Uso 1: taxa de recuperacao de um usuario especifico
SELECT full_name, fn_taxa_recuperacao_usuario(id) AS taxa_recuperacao_pct
FROM app_users
WHERE id = '22222222-2222-2222-2222-222222222222';

-- Uso 2: taxa de recuperacao de TODOS os usuarios, do maior para o menor
SELECT
  full_name,
  fn_taxa_recuperacao_usuario(id) AS taxa_recuperacao_pct
FROM app_users
ORDER BY taxa_recuperacao_pct DESC NULLS LAST;

-- Uso 3: resumo formatado de um item especifico
SELECT fn_resumo_item_formatado(2) AS resumo FROM dual;

-- Uso 4: resumo formatado de TODOS os itens (uso tipico em tela de listagem)
SELECT id, fn_resumo_item_formatado(id) AS resumo
FROM items
ORDER BY id;
