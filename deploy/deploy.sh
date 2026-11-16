#!/usr/bin/env bash
# Deploy por "pull": roda a cada minuto (systemd timer) na VM.
# Se o GitHub Actions publicou uma imagem nova no GHCR, ela é baixada e a API reinicia.
# Nenhuma porta de administração precisa ficar aberta para o GitHub.
set -euo pipefail
cd /opt/calcada
docker compose -f docker-compose.prod.yml pull --quiet api
docker compose -f docker-compose.prod.yml up -d --remove-orphans
docker image prune -f >/dev/null
