#!/usr/bin/env bash
# Gera tráfego normal + erros forçados para demonstrar o dashboard e disparar o alerta.
# Uso: ./monitoring/gerar_trafego.sh https://SEU-DOMINIO 300   (segundos)
set -u
URL="${1:?informe a URL do MVP}"
DURACAO="${2:-300}"
FIM=$(( $(date +%s) + DURACAO ))
echo "Gerando tráfego em $URL por ${DURACAO}s (Ctrl+C para parar)..."
while [ "$(date +%s)" -lt "$FIM" ]; do
  curl -s -o /dev/null "$URL/api/v1/ocorrencias"
  curl -s -o /dev/null "$URL/health"
  curl -s -o /dev/null "$URL/teste/erro"   # 500 de propósito (CHAOS_ENABLED=true)
  sleep 0.5
done
echo "Pronto. Veja o alerta TaxaDeErro5xxAlta em http://localhost:9090/alerts"
