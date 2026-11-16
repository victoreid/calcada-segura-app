# CLAUDE.md: instruções para o Claude Code neste repositório

## Quem é o usuário e como falar com ele

- **Victor Eid Carbutti Nicolas (RM98668)**, aluno do 4º ano de Engenharia de Software da FIAP.
- Fale sempre em **português do Brasil**, como para um **iniciante**: frases curtas, sem jargão sem explicar.
- O computador dele é **Windows**. Use **PowerShell**. Se algo exigir Linux, use o WSL e avise antes.
- **Um passo por vez.** Para cada passo:
  1. Explique o que vamos fazer e por quê (2 ou 3 linhas).
  2. Rode o comando, ou diga exatamente onde ele deve clicar.
  3. Confira se funcionou.
  4. Diga se precisa de print para o PDF e de quê.
  5. **Espere ele confirmar** antes de avançar.
- Se algo exigir ação dele no navegador (login na Azure ou no GitHub, mudar a visibilidade do pacote), diga o caminho clique por clique.
- Nunca mostre senha, chave ou token inteiro na tela. Nunca commite `.env`, `terraform.tfvars` ou `*.tfstate`.

## Contexto do trabalho

- **FIAP Global Solution 2026.2 · CitizenTech.** O produto do grupo é o **Calçada Segura**: mapeia buracos, rampas fora da norma (NBR 9050, limite de 8,33%) e barreiras nas calçadas de São Paulo.
- **Grupo:** Eid (Victor), JP, Enzão e Tiagão. Victor entrega **Secure DevOps & Cloud** (este repositório) e **Maker Lab** (o robô, em outro repositório).
- **Prazo: 19/11/2026 às 23h55**, pelo Teams da disciplina. A meta do grupo é enviar até as 20h. Hoje é dia 16/11.
- A URL pública precisa **continuar no ar por até uma semana depois de 19/11**, durante a correção. Não destruir a infraestrutura nem deixar o crédito acabar.

## O que a disciplina pede (Deploy Blindado, 14 pontos)

| Item | Pontos | Onde está neste repositório |
|---|---|---|
| Dockerfile enxuto, usuário não root, sem segredo na imagem, stack com docker compose | 2,0 | `Dockerfile`, `docker-compose.yml` |
| Nuvem criada por Terraform, state e `.tfvars` fora do repositório, porta de administração nunca aberta para 0.0.0.0/0 | 3,0 | `terraform/` |
| GitHub Actions com build, Gitleaks, Semgrep e Trivy a cada push, segredos no GitHub Secrets, deploy automático, **uma execução barrada e a corrigida** | 4,0 | `.github/workflows/devsecops.yml`, `docs/demo_segredo_vazado.sh` |
| Dashboard com as 4 métricas de ouro (Prometheus + Grafana) e **um alerta disparado** | 3,0 | `monitoring/` |
| Diagrama da arquitetura, responsabilidade compartilhada, onde ficam os dados pessoais (LGPD), estimativa de custo, README reproduzível | 2,0 | `README.md` + PDF |

**Entregáveis:** repositório público com Dockerfile, workflow e Terraform, mais a Ficha Técnica no README. A URL pública do MVP. **Um PDF único com links clicáveis**, com arquitetura, evidências (prints) e custo. Um envio por equipe.

## Arquitetura escolhida (não mudar sem motivo forte)

- **Azure for Students** (conta da FIAP). Uma VM Ubuntu 24.04 `Standard_B1ms` criada por Terraform. Nela rodam Caddy (HTTPS automático com Let's Encrypt, no domínio `*.cloudapp.azure.com`), a API e o Postgres, via docker compose.
- **NSG:** 80/443 abertos (é o site público); a porta 22 só abre para `admin_ip_cidr`, e o Terraform recusa `0.0.0.0/0`.
- **Deploy "por pull":** o pipeline publica a imagem no **GHCR** e um timer do systemd na VM puxa a imagem nova a cada minuto. O job `deploy` do pipeline confirma, em `/health`, que a versão nova (o SHA do commit) entrou no ar. Escolhido porque conta de estudante costuma bloquear a criação de Service Principal, e porque assim nenhuma porta de administração fica aberta para o GitHub.
- **/metrics** fica protegido por basic auth no Caddy (usuário `prometheus`, senha na saída `metrics_password` do Terraform).
- **A API em `app/` é PROVISÓRIA.** Ela segue o contrato do grupo para que a infraestrutura possa ser testada. A API definitiva pode vir do colega (Tiagão). Quando vier, ela precisa manter `GET /health` (com o campo `versao`, lido de `APP_VERSION`), `GET /metrics` e a porta 8000.

### Contrato da ocorrência (o grupo inteiro usa)

```json
{ "id": "uuid", "origem": "robo|visao|cidadao",
  "tipo": "buraco|calcada_quebrada|obstaculo|rampa_irregular|trepidacao|degrau",
  "lat": -23.5614, "lon": -46.6559, "foto_url": "...", "confianca": 0.87,
  "inclinacao_pct": 11.2, "vibracao_rms": 0.42, "criado_em": "ISO-8601",
  "status": "nova|validada|duplicada|priorizada|encaminhada|resolvida",
  "prioridade": "alta|media|baixa", "subprefeitura": "Pinheiros" }
```

A escrita exige o header `X-API-Key`. Hoje as rotas estão em `/api/v1/ocorrencias`.

## Roteiro: siga nesta ordem, um passo por vez

### Fase 1: preparar o computador
- Conferir com `git --version`, `docker --version`, `az --version`, `terraform --version`.
- Instalar o que faltar com `winget`:
  - `Git.Git`
  - `Docker.DockerDesktop` (exige o WSL2; reiniciar se pedir)
  - `Microsoft.AzureCLI`
  - `Hashicorp.Terraform`
- Depois de instalar, fechar e reabrir o PowerShell.
- Chave SSH: `ssh-keygen -t ed25519` (aceitar o caminho padrão).

### Fase 2: GitHub
- **Primeiro:** o pipeline está em `ci/devsecops.yml` (a ferramenta que copiou a pasta não pode gravar dentro de `.github`). Mova para o lugar certo:
  `New-Item -ItemType Directory -Force .github\workflows; Move-Item ci\devsecops.yml .github\workflows\devsecops.yml; Remove-Item ci`
- **Atenção:** esta pasta está dentro do **OneDrive**. O OneDrive pode travar arquivos do Git e do Docker. Se der erro estranho de arquivo em uso, sugira mover o projeto para `C:\dev\calcada-segura-app`.
- Repositório **público** `calcada-segura-app`, de preferência na organização do grupo (ex.: `calcada-segura`).
- `git init`, `git add`, `git commit` e `git push` para a `main`. Confira antes que `git status` não lista `.env` nem `terraform.tfvars`.

### Fase 3: rodar localmente
- `copy .env.example .env`, trocar as senhas e rodar `docker compose up --build`.
- Testar: `http://localhost:8000/health` e `/docs`. Criar uma ocorrência pelo `/docs` usando a `API_KEY` do `.env`.
- **Print:** `docker compose ps` e o `/health` respondendo.

### Fase 4: pipeline verde
- Em Actions, acompanhar o workflow **DevSecOps**.
- **Se algum scanner (Semgrep ou Trivy) acusar problema, corrija a causa.** Não desligue o scanner nem baixe a severidade só para passar. Se for um falso positivo justificável (como o 80/443 aberto no NSG, que é o site público), use um ignore pontual com comentário explicando.
- Depois do primeiro push na `main` que passar: GitHub → perfil ou organização → **Packages** → `calcada-segura-app` → **Package settings** → **Change visibility** → **Public**. Sem isso, a VM não consegue baixar a imagem.
- **Print:** a execução verde com todos os jobs.

### Fase 5: Azure com Terraform
- `az login`, depois `az account show --query id -o tsv` (é a `subscription_id`).
- Pegar o IP público com `curl ifconfig.me` e usar com `/32`.
- `cd terraform`, `copy terraform.tfvars.example terraform.tfvars` e preencher. A imagem vai em minúsculas: `ghcr.io/<dono>/calcada-segura-app:latest`.
- Rodar `terraform init`, `terraform plan` e `terraform apply`.
- Se der erro de política de região ou de capacidade: `location = "eastus2"` e/ou `vm_size = "Standard_B2s"`.
- Esperar de 3 a 5 minutos (cloud-init) e abrir `terraform output url_mvp`.
- Para investigar: `ssh azureuser@<ip>`, depois `sudo cloud-init status --long`, `sudo docker ps` e `journalctl -u calcada-deploy`.
- **Print:** a saída do `apply`, o Resource Group no portal da Azure, a regra do NSG com o SSH restrito e o site em HTTPS.
- Passar a `terraform output -raw api_key` para o grupo **só em mensagem privada**.

### Fase 6: deploy automático
- GitHub → Settings → Secrets and variables → Actions → **Variables** → `MVP_URL` = a URL do MVP.
- Fazer uma mudança pequena (ex.: um texto em `app/static/index.html`), dar push e ver o job **Deploy** confirmar a versão nova.
- **Print:** o job Deploy verde e o `/health` mostrando o SHA novo.

### Fase 7: execução barrada
- Rodar `docs/demo_segredo_vazado.sh` (no Git Bash ou no WSL), a partir da `main` limpa.
- **Print:** o Gitleaks vermelho na branch `demo/segredo-vazado` e depois a execução verde. A branch é apagada no fim; **a chave falsa nunca pode chegar à `main`**.

### Fase 8: observabilidade
- Criar `monitoring/secrets/metrics_password` com `terraform -chdir=terraform output -raw metrics_password`, sem quebra de linha no final.
- Em `monitoring/prometheus.yml`, trocar o domínio no `targets`.
- Rodar `docker compose -f monitoring/docker-compose.monitoring.yml up -d`.
- Conferir em `localhost:9090/targets` que o alvo está **UP**. Abrir o Grafana (`localhost:3000`) → dashboard **"Calçada Segura · 4 métricas de ouro"**.
- Rodar `monitoring/gerar_trafego.sh <URL> 300` e ver `TaxaDeErro5xxAlta` em **FIRING** em `localhost:9090/alerts`.
- Depois da demonstração: na VM, mudar `CHAOS_ENABLED=false` em `/opt/calcada/.env` e rodar `sudo /opt/calcada/deploy.sh`.
- **Print:** o dashboard com os 4 painéis e o alerta em FIRING.

### Fase 9: PDF de entrega
Um PDF único, com links clicáveis, nesta ordem:

1. Capa: nomes completos e RMs dos 4.
2. Ficha Técnica.
3. URL do MVP e do repositório.
4. Diagrama da arquitetura.
5. Container e IaC, com prints.
6. Pipeline, com a execução barrada e a corrigida.
7. Observabilidade, com o dashboard e o alerta.
8. Responsabilidade compartilhada.
9. LGPD (onde ficam os dados pessoais).
10. Estimativa de custo (print da calculadora da Azure: B1ms 730 h, disco Standard 30 GB, IP público estático, Brazil South).
11. Conclusão.

## Pendências conhecidas

- Os nomes completos e RMs de JP, Enzão e Tiagão ainda faltam no README e no PDF. Perguntar ao Victor.
- Trocar a API provisória pela definitiva quando o colega entregar, mantendo `/health` e `/metrics`.
- O dashboard do cidadão (mapa) é do colega; aqui há só uma página provisória em `app/static/index.html`.
