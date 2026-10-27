"""Gera o resumo da execucao do pipeline em Markdown.

Le os relatorios XML do Maven Surefire e o log dos testes PL/SQL e escreve
uma tabela no resumo do GitHub Actions (variavel GITHUB_STEP_SUMMARY) e em
um arquivo Markdown que vai junto com os artefatos da execucao.

Uso: python resumo_testes.py <pasta_surefire> <log_testes_plsql> <arquivo_saida.md>
"""

import glob
import os
import sys
import xml.etree.ElementTree as ET


def ler_surefire(pasta):
    linhas, totais = [], {"testes": 0, "falhas": 0, "erros": 0, "ignorados": 0, "tempo": 0.0}
    for arquivo in sorted(glob.glob(os.path.join(pasta, "TEST-*.xml"))):
        raiz = ET.parse(arquivo).getroot()
        nome = raiz.get("name", "").split(".")[-1]
        testes = int(raiz.get("tests", 0))
        falhas = int(raiz.get("failures", 0))
        erros = int(raiz.get("errors", 0))
        ignorados = int(raiz.get("skipped", 0))
        tempo = float(raiz.get("time", 0) or 0)
        totais["testes"] += testes
        totais["falhas"] += falhas
        totais["erros"] += erros
        totais["ignorados"] += ignorados
        totais["tempo"] += tempo
        situacao = "OK" if falhas == 0 and erros == 0 else "FALHA"
        linhas.append(f"| {nome} | {testes} | {falhas + erros} | {ignorados} | {tempo:.1f}s | {situacao} |")
    return linhas, totais


def ler_plsql(log):
    if not os.path.exists(log):
        return []
    with open(log, encoding="utf-8", errors="replace") as f:
        return [l.strip() for l in f if l.strip().startswith(("[OK]", "[FALHA]"))]


def main():
    pasta_surefire, log_plsql, saida = sys.argv[1], sys.argv[2], sys.argv[3]
    linhas, totais = ler_surefire(pasta_surefire)
    plsql = ler_plsql(log_plsql)

    md = ["## Relatório de execução: BipTag API", ""]
    md.append(f"Commit `{os.environ.get('GITHUB_SHA', 'local')[:7]}` na branch "
              f"`{os.environ.get('GITHUB_REF_NAME', 'local')}`, execução #{os.environ.get('GITHUB_RUN_NUMBER', '-')}.")
    md.append("")
    md.append("### Testes automatizados da API (JUnit + Oracle)")
    md.append("")
    md.append("| Classe de teste | Testes | Falhas | Ignorados | Tempo | Situação |")
    md.append("|---|---|---|---|---|---|")
    md.extend(linhas or ["| (nenhum relatório encontrado) | - | - | - | - | - |"])
    md.append(f"| **Total** | **{totais['testes']}** | **{totais['falhas'] + totais['erros']}** "
              f"| **{totais['ignorados']}** | **{totais['tempo']:.1f}s** | |")
    md.append("")
    md.append("### Testes do banco de dados (PL/SQL)")
    md.append("")
    if plsql:
        aprovados = sum(1 for l in plsql if l.startswith("[OK]"))
        md.append(f"{aprovados} de {len(plsql)} verificações aprovadas.")
        md.append("")
        md.extend(f"- `{l}`" for l in plsql)
    else:
        md.append("Log dos testes PL/SQL não encontrado.")
    md.append("")

    texto = "\n".join(md)
    with open(saida, "w", encoding="utf-8") as f:
        f.write(texto)
    resumo = os.environ.get("GITHUB_STEP_SUMMARY")
    if resumo:
        with open(resumo, "a", encoding="utf-8") as f:
            f.write(texto + "\n")
    print(texto)


if __name__ == "__main__":
    main()
