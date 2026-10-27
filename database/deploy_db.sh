#!/usr/bin/env bash
#
# Aplica scripts SQL em um banco Oracle usando o SQL*Plus.
# Usado pelo pipeline de CI/CD (dentro do container Oracle) e no deploy manual.
#
# Uso:
#   ./deploy_db.sh "<usuario>/<senha>@//<host>:<porta>/<servico>" <pasta_de_logs> script1.sql [script2.sql ...]
#
# Cada script gera um log proprio. A execucao para no primeiro erro de SQL
# ou na primeira compilacao com erros de package, procedure ou trigger.

set -uo pipefail

CONEXAO="$1"
PASTA_LOGS="$2"
shift 2

mkdir -p "$PASTA_LOGS"
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8

for SCRIPT in "$@"; do
  NOME=$(basename "$SCRIPT" .sql)
  LOG="$PASTA_LOGS/$NOME.log"
  echo ""
  echo "=================================================================="
  echo ">> Executando $SCRIPT"
  echo "=================================================================="

  sqlplus -s -L "$CONEXAO" > "$LOG" 2>&1 <<SQL
WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR EXIT FAILURE
SET DEFINE OFF
SET ECHO OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
@$SCRIPT
EXIT SUCCESS
SQL
  CODIGO=$?

  cat "$LOG"

  if [ $CODIGO -ne 0 ]; then
    echo "::error::Falha ao executar $SCRIPT (codigo $CODIGO). Veja o log acima."
    exit 1
  fi

  if grep -qiE "created with compilation errors|Warning: .*compilation errors" "$LOG"; then
    echo "::error::$SCRIPT gerou objetos com erros de compilacao."
    sqlplus -s -L "$CONEXAO" <<SQL
SET LINESIZE 220
SET PAGESIZE 200
COLUMN text FORMAT A120
SELECT name, type, line, position, text FROM user_errors ORDER BY name, type, sequence;
EXIT
SQL
    exit 1
  fi

  echo ">> $SCRIPT concluido com sucesso."
done
