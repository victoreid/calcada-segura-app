# Calçada Segura · MVP (API + infraestrutura)

> FIAP · Global Solution 2026.2 · CitizenTech · Engenharia de Software 4º ano
> Disciplina: **Secure DevOps Tools & Cloud Computing** · Atividade: *Deploy Blindado*

## Integrantes

| Nome completo | RM |
|---|---|
| Victor Eid Carbutti Nicolas | RM98668 |
| João Pedro Cruz | RM98650 |
| Enzo Luiz Goulart | RM99666 |
| Tiago Paulino | RM551169 |

## Ficha Técnica do MVP

| Campo | Conteúdo |
|---|---|
| Nome do produto | Calçada Segura |
| Cidadão e território | Pedestres, pessoas com deficiência e idosos nas calçadas urbanas de São Paulo |
| Problema, em uma frase | Calçadas com buracos, rampas fora da norma e barreiras impedem a mobilidade e causam quedas, e não são mapeadas nem priorizadas. |
| Proposta de valor | Mapa priorizado das falhas de calçada, gerado por robô, visão computacional e cidadão, com orientação sobre direitos e reparo. |
| Arquitetura: componentes | Robô (Maker Lab) · Visão YOLO · RPA de triagem · Airflow + Databricks · Assistente RAG com LLM local · **API central + dashboard na Azure (este repositório)** · Pitch |
| Fontes de dados | Ocorrências do robô e da visão · SP156 (dados abertos) · Open-Meteo |
| Modelos de IA utilizados | YOLO (detecção) · LLM local com RAG · classificador das leituras do robô |
| URL do MVP e repositório | https://calcada-segura-nc-6iey3.northcentralus.cloudapp.azure.com · https://github.com/victoreid/calcada-segura-app |
| Indicadores de impacto | Problemas mapeados e críticos por subprefeitura · % triados em até 24 h · tempo médio até o conserto · % de rampas dentro de 8,33% |
| ODS conectados | 11 · 10 · 9 · 3 |

## Arquitetura

```
 Desenvolvedor ──push──► GitHub Actions
                           ├─ Gitleaks (segredos no histórico)
                           ├─ Semgrep  (SAST: Python, Dockerfile, Terraform)
                           ├─ Testes   (pytest)
                           ├─ Build da imagem + Trivy (imagem, dependências, IaC)
                           ├─ Push ──► GHCR (ghcr.io/<org>/calcada-segura-app)
                           └─ Deploy: confirma a versão nova em /health

 Azure (criada 100% por Terraform) - região North Central US
 ┌──────────────── Resource Group rg-calcada-segura-nc ──────────────┐
 │ NSG: 443/80 abertos (site) · 22 SOMENTE para o IP do administrador │
 │ VM Ubuntu 24.04 (Standard_B2als_v2: 2 vCPU, 4 GiB)                 │
 │   ├─ Caddy  → HTTPS automático (Let's Encrypt) + headers seguros  │
 │   ├─ API FastAPI (container, usuário não root, read-only)         │
 │   ├─ PostgreSQL 16 (container, sem porta exposta)                 │
 │   └─ timer systemd: puxa a imagem nova do GHCR a cada minuto      │
 └────────────────────────────────────────────────────────────────────┘
        ▲ HTTPS                                   ▲ HTTPS + basic auth em /metrics
   Cidadão / Robô / Visão / RPA            Prometheus + Grafana (máquina local)
```

**Por que deploy por "pull":** a VM busca a imagem nova sozinha. O GitHub nunca precisa de acesso SSH nem de credencial da Azure, então a porta de administração fica fechada para todo mundo menos o administrador, e nenhum segredo de nuvem fica no GitHub.

## Estrutura

```
app/                      API FastAPI (provisória, segue o contrato do grupo)
tests/                    testes (pytest)
Dockerfile                multi-stage, slim, usuário não root, healthcheck
docker-compose.yml        ambiente local (api + db)
deploy/                   compose de produção, Caddyfile, script de deploy
terraform/                infraestrutura Azure (VM, rede, NSG, IP, cloud-init)
.github/workflows/        pipeline DevSecOps
monitoring/               Prometheus, alertas, Grafana (4 métricas de ouro)
docs/                     script da demonstração do Gitleaks
```

## 1. Rodar localmente

```bash
cp .env.example .env          # troque as senhas
docker compose up --build
curl http://localhost:8000/health
```

## 2. Publicar na Azure (uma vez)

Pré-requisitos: Azure CLI, Terraform ≥ 1.6, chave SSH (`ssh-keygen -t ed25519`).

```bash
# 2.1 Publicar a imagem: faça push na main e espere o pipeline passar.
#     Depois, no GitHub: Packages > calcada-segura-app > Package settings > Change visibility > Public

# 2.2 Criar a infraestrutura
az login
cd terraform
cp terraform.tfvars.example terraform.tfvars   # preencha (subscription, seu IP /32, imagem, e-mail)
terraform init
terraform plan
terraform apply

terraform output url_mvp                  # URL pública do MVP
terraform output -raw api_key             # X-API-Key para Robô, Visão e RPA (mandar no privado)
```

Em 3 a 5 minutos o cloud-init instala o Docker, sobe a stack e o Caddy emite o certificado HTTPS.

```bash
# 2.3 Ligar a verificação de deploy no pipeline
# GitHub > Settings > Secrets and variables > Actions > Variables > New variable
#   MVP_URL = (saída url_mvp)
```

## 3. Pipeline DevSecOps

A cada push: **Gitleaks → Semgrep → testes → build → Trivy → push no GHCR → deploy**. Qualquer achado CRITICAL/HIGH ou segredo vazado barra o pipeline. Segredos só existem no GitHub Secrets (o `GITHUB_TOKEN` para o GHCR) e no state do Terraform, que nunca vai para o Git.

### Demonstração da execução barrada (pedida pelo professor)

Faça numa branch separada, para a chave falsa nunca entrar no histórico da `main`. O script monta a chave falsa só na hora:

```bash
./docs/demo_segredo_vazado.sh
```

1. Ele cria a branch `demo/segredo-vazado`, commita uma chave AWS falsa e faz push. O **Gitleaks reprova**: tire o print.
2. Ele desfaz o commit e faz push de novo. O **pipeline fica verde**: tire o print.
3. Ele apaga a branch.

## 4. Observabilidade

```bash
mkdir -p monitoring/secrets
terraform -chdir=terraform output -raw metrics_password > monitoring/secrets/metrics_password
# edite monitoring/prometheus.yml e troque o domínio
docker compose -f monitoring/docker-compose.monitoring.yml up -d
```

- Prometheus: http://localhost:9090 · Grafana: http://localhost:3000 (admin/admin no primeiro acesso)
- Dashboard **"Calçada Segura · 4 métricas de ouro"**: latência (p50/p95/p99), tráfego, erros (5xx/4xx) e saturação (CPU, memória, requisições em andamento).
- Alertas: `TaxaDeErro5xxAlta`, `LatenciaP95Alta`, `MVPForaDoAr`, `MemoriaAlta`.
- Disparar o alerta de verdade: `./monitoring/gerar_trafego.sh https://<url_mvp> 300` e abrir http://localhost:9090/alerts (estado **FIRING**). Depois da demonstração, troque `CHAOS_ENABLED=false` no `/opt/calcada/.env` da VM.

## 5. Segurança e LGPD

| Controle | Onde |
|---|---|
| Usuário não root, imagem slim, sem segredo na imagem, filesystem read-only | `Dockerfile`, `docker-compose*.yml` |
| SSH só para o IP do administrador (validação impede `0.0.0.0/0`), senha desativada | `terraform/variables.tf`, `terraform/main.tf` |
| HTTPS obrigatório, HSTS e headers de segurança | `deploy/Caddyfile.tftpl` |
| `/metrics` protegido por senha | Caddy `basic_auth` |
| Escrita na API exige `X-API-Key` (variável de ambiente) | `app/main.py` |
| Banco sem porta exposta, senha gerada pelo Terraform | `deploy/docker-compose.prod.yml` |
| State e `.tfvars` fora do Git | `.gitignore` |

**Dados pessoais:** a API não guarda nome, e-mail nem telefone de ninguém. Os dados sensíveis são a **localização** (devolvida sempre com 4 casas decimais, cerca de 11 m) e as **fotos** (rostos e placas borrados pela Visão antes do envio). Ficam no PostgreSQL dentro da VM, em disco gerenciado da Azure, na região **North Central US** (EUA). A conta Azure for Students da FIAP só permite 5 regiões (southcentralus, eastus2, northcentralus, chilecentral e canadacentral), e `brazilsouth` é bloqueada por política. Como os dados são apenas coordenadas aproximadas e fotos com rostos e placas borrados, sem identificação de pessoas, o risco de uma transferência internacional é baixo. Em produção real, a base ficaria em uma região do Brasil (LGPD, art. 33).

## 6. Responsabilidade compartilhada (IaaS)

| Azure | Equipe |
|---|---|
| Data center, hardware, rede física, hipervisor | Sistema operacional da VM e atualizações |
| Disponibilidade da região e do disco gerenciado | Regras do NSG, chaves SSH, segredos |
| Plataforma do Let's Encrypt (terceiro) | Containers, imagem, dependências e vulnerabilidades |
| | Dados e LGPD, backup do banco, monitoramento e alertas |

## 7. Estimativa de custo

Monte em https://azure.microsoft.com/pricing/calculator com: 1 VM Linux Standard_B2als_v2 (730 h/mês, 2 vCPU e 4 GiB, cerca de US$ 27,45/mês no portal), 1 disco gerenciado Standard HDD 30 GB, 1 IP público Standard estático, tráfego de saída baixo, na região North Central US (a mesma que está em produção). O GHCR e o GitHub Actions são gratuitos para repositório público. Coloque o print da calculadora no PDF.

> Não desligue a VM antes do fim da correção (até uma semana após 19/11).
