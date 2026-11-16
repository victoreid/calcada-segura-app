#!/usr/bin/env bash
# Demonstração da execução barrada pelo Gitleaks (rodar a partir da main, com tudo commitado).
# A chave falsa é montada só na hora, para nunca existir no histórico da main.
set -euo pipefail
git checkout -b demo/segredo-vazado
PREFIXO="AKIA"; RESTO="Z7QW4XMPLE9TEST2"
printf 'AWS_ACCESS_KEY_ID = "%s%s"\n' "$PREFIXO" "$RESTO" > config_demo.py
git add config_demo.py
git commit -m "demo: segredo vazado (deve ser barrado)"
git push -u origin demo/segredo-vazado
echo ">> Abra o Actions: o job Gitleaks deve ficar VERMELHO. Tire o print."
read -rp ">> Depois do print, aperte Enter para corrigir..."
git reset --hard HEAD~1
git push --force
echo ">> Pipeline da branch corrigida deve ficar VERDE. Tire o print."
read -rp ">> Depois do print, aperte Enter para apagar a branch..."
git checkout main
git branch -D demo/segredo-vazado
git push origin --delete demo/segredo-vazado
