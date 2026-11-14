# Tech Challenge — Fase 04 (ToggleMaster)

> Fonte: `POSTECH - Tech Challenge - Fase 4-1.pdf` (salvo nesta pasta como referência). Este arquivo é o resumo estruturado para consulta rápida durante o desenvolvimento — em caso de dúvida, o PDF original é a fonte de verdade.

## Contexto do programa

- Vale **90% da nota** de todas as disciplinas da fase. Obrigatório.
- **Projeto evolutivo e cumulativo**: é a conclusão da jornada ToggleMaster (Fases 1→4). É **obrigatório** que a base das Fases 1, 2 e 3 esteja funcionando:
  - 5 microsserviços conteinerizados (auth, flag, targeting, evaluation, analytics).
  - Infraestrutura provisionada via Terraform.
  - Pipelines CI/CD (GitHub Actions) com DevSecOps.
  - Implantação no Kubernetes (EKS) gerenciada via GitOps (ArgoCD).
- O monitoramento desta fase é construído **em cima** dessa arquitetura — não substitui nada da Fase 03.

## O desafio (narrativa)

`evaluation-service` falhou silenciosamente num fim de semana. O HPA escalou automaticamente tentando compensar, consumo de recursos disparou. Time só soube 6h depois (via usuários) e levou mais 4h para achar a causa raiz em logs espalhados pelos pods.

**Objetivo:** Observabilidade Total + Resposta Ativa:
- Serviço lento → ver o **Trace**.
- Erro → **Logs centralizados**.
- Limite atingido → time **acordado via PagerDuty/OpsGenie**.
- Sistema deve tentar **se curar sozinho** (Self-Healing).

## Requisitos técnicos

### 1. Monitoramento Opensource (Métricas e Logs no K8s)
*Disciplinas: Prometheus, Grafana, Loki, Observabilidade no Kubernetes*

Provisionar via Helm charts **adicionados ao repositório GitOps** (não kubectl manual):
- **Prometheus** — métricas de infraestrutura.
- **Loki** — centralização/indexação de logs de todos os contêineres do cluster.
- **Grafana** — visualização principal.
  - Mínimo **1 dashboard customizado** cobrindo: uso de recursos do cluster, taxa de requisições dos microsserviços, painel de logs em tempo real.

### 2. OpenTelemetry (OTel) e Padronização
*Disciplinas: OpenTelemetry e Alloy*

- **OTel Collector é obrigatório** — peça central que recebe métricas/logs/traces dos microsserviços e roteia para os backends corretos (Prometheus, Loki, APM).
- Grafana Alloy no lugar do OTel Collector padrão é **opcional** (não obrigatório).

### 3. Instrumentação e APM (Traces e Visibilidade Profunda)
*Disciplinas: APM, Instrumentação, Datadog ou New Relic*

- Escolher **UMA** ferramenta comercial: **Datadog OU New Relic** (conta gratuita/education).
- Instrumentar código-fonte ou Dockerfile dos microsserviços com bibliotecas de instrumentação (preferencialmente libs OpenTelemetry da linguagem — Go para auth/evaluation, Python para flag/targeting/analytics).
- **Distributed Tracing**: requisição no evaluation-service deve mostrar o "caminho" completo no APM.
- **Service Map**: painel do APM deve exibir o mapa de dependências dos 5 microsserviços.

### 4. Alertas Inteligentes e Self-Healing
*Disciplinas: Alert Fatigue, PagerDuty/OpsGenie, ChatOps, Runbook Automation, Self-Healing*

- **Alerta inteligente** (Grafana ou APM). Exemplo do enunciado: HTTP 5xx do auth-service > 5%.
- **Gerenciamento de incidentes**: conta no **PagerDuty OU OpsGenie**, integrada para abrir incidente automaticamente a partir do alerta.
- **ChatOps**: notificação detalhada para canal **Slack, Discord ou Teams**.
- **Self-Healing (obrigatório)**: automação (Runbook Automation / AWS Lambda / GitHub Action via webhook) que reage automaticamente ao alerta. Exemplo do enunciado: `kubectl rollout restart deployment/auth-service` disparado sem intervenção humana.

## Entregáveis

### Código no repositório
- IaC/GitOps atualizado com a stack de monitoramento + OTel Collector.
- Código-fonte das aplicações atualizado com instrumentação.
- Scripts/automações do Self-Healing.

### Vídeo de demonstração (até 25 min)
1. **Visão geral** — EKS (IaC) e ArgoCD (GitOps) continuam rodando, agora com a nova stack.
2. **Métricas, Logs e OTel** — Grafana aberto, dashboard customizado com métricas reais, busca de logs no Loki, explicação de como o OTel Collector roteia os dados.
3. **APM e Tracing** — painel Datadog/New Relic, Service Map, requisição de teste com Trace Distribuído detalhado.
4. **Incidente e Self-Healing (a prova real)**:
   - Causar problema proposital (ex.: derrubar o banco do flag-service, ou injetar erro no código).
   - Mostrar alerta disparando (Firing) no Grafana/APM.
   - Mostrar incidente aberto no PagerDuty/OpsGenie + notificação no Slack/Discord.
   - Mostrar a automação de Self-Healing executando a correção (ex.: pod reiniciando, visível no terminal).

**Regra de avaliação:** tudo que não for claramente demonstrado no vídeo ou documentado no relatório perde pontos diretamente. Não basta configurar — precisa mostrar operando na prática.

### Relatório de entrega (.PDF)
- Nomes, RMs, usernames.
- Links do repositório e do vídeo.
- **Evidências visuais obrigatórias**: print do dashboard Grafana, print de um trace distribuído no APM, print da notificação de incidente no ChatOps, print do log/execução do Self-Healing.
- **Justificativa técnica**: arquitetura OTel implementada; por que Datadog vs New Relic; por que OpsGenie vs PagerDuty.

## Decisões deste projeto

- **APM:** Datadog (free trial / education tier).
- **Incident management:** PagerDuty.
- **ChatOps:** Slack.
- **Self-healing trigger:** GitHub Action disparada via webhook (Alertmanager → repository_dispatch → Action assume a IAM role via OIDC já existente da Fase 03 → `kubectl rollout restart`). Reaproveita a federação OIDC GitHub↔AWS da Fase 03, sem infra nova de Lambda.
- **Repositório:** novo repo `togglemaster-fase04`, iniciado a partir do conteúdo atual do `togglemaster-fase03` (histórico de git não é herdado — fresh init — para não carregar estado/segredos antigos).

## Estado herdado da Fase 03

- Cluster EKS `togglemaster` **não está ativo no momento** (`aws eks list-clusters` retornou vazio em 2026-11-14) — infraestrutura foi destruída desde a última sessão. Precisa reaplicar o Terraform da Fase 03 antes de começar a empilhar a stack de observabilidade.
- Repo Fase 03: `github.com/pedrohenriqueortizcosta-blip/togglemaster-fase03`.
- Ainda não existe repositório `togglemaster-fase04` no GitHub do usuário.
