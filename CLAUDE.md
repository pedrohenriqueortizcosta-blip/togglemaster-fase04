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

- Cluster EKS `togglemaster` **não está ativo no momento** (`aws eks list-clusters` retornou vazio em 2026-11-14) — infraestrutura foi destruída desde a última sessão. Precisa reaplicar o Terraform antes de empilhar a stack de observabilidade.
- Repo Fase 03: `github.com/pedrohenriqueortizcosta-blip/togglemaster-fase03`.
- Repo Fase 04: `github.com/pedrohenriqueortizcosta-blip/togglemaster-fase04` — criado em 2026-11-14, seedado a partir do HEAD commitado da Fase 03 (histórico de git novo). **Criado como privado** (restrição da sessão contra criar superfícies públicas automaticamente) — lembrar de torná-lo público (ou adicionar os avaliadores como colaboradores) antes da entrega final, já que o link do repositório vai no relatório.
- **Terraform state compartilhado**: `terraform/backend.tf` aponta para o mesmo S3 state da Fase 03 (`togglemaster/fase03/terraform.tfstate`) — decisão deliberada (2026-11-15) de continuar a mesma linhagem de ambiente em vez de recriar do zero. **A partir de agora, `togglemaster-fase03` deve ser tratado como congelado/arquivado** — nenhum `terraform apply` deve rodar a partir daquele repo, só a partir do `togglemaster-fase04`, para evitar dois repositórios disputando o mesmo state.

## Fase 0 — status (2026-11-15): base reaplicada com sucesso

Infra da Fase 03 reaplicada do zero sob o repo `togglemaster-fase04`. 5 microsserviços `Running`/`Healthy`, todas as 5 ArgoCD Applications `Synced`, todos os 5 pipelines de CI passando de ponta a ponta (incluindo build→push→bump do gitops→sync do ArgoCD).

**Problemas reais encontrados e corrigidos neste processo (bons candidatos para a seção de "desafios" do relatório):**

1. **CRD do ArgoCD em cluster novo** — `kubernetes_manifest.argocd_app` precisa que a CRD `Application` já exista no momento do `plan`, mas ela só é criada pelo próprio `helm_release.argocd`. Resolvido renomeando temporariamente `argocd-apps.tf` → `.disabled`, aplicando tudo mais primeiro (cria o cluster + instala ArgoCD, criando a CRD), depois restaurando o arquivo e aplicando de novo — mesma técnica documentada na Fase 03, desta vez a partir de um state 100% vazio.
2. **Variável `github_repository` ainda apontando para `fase03`** — afetava tanto a trust policy OIDC do GitHub Actions (bloqueava toda autenticação CI→AWS) quanto o `repoURL` das 5 Applications do ArgoCD (watch no repo errado). Corrigido o default em `variables.tf`; replan mostrou exatamente 1 IAM role atualizada in-place + 5 Applications criadas com o `repoURL` certo.
3. **Variável de repositório `AWS_ROLE_ARN` nunca configurada no novo repo** — Secrets/Variables do GitHub não são versionados em git, então não vieram no "seed" a partir da Fase 03. Resolvido com `gh variable set AWS_ROLE_ARN`.
4. **Race condition real em CI concorrente** — os 5 pipelines rodando em paralelo pela primeira vez (nunca tinha acontecido na Fase 03) expôs duas falhas latentes no workflow template:
   - Dois+ pipelines tentando commitar seu próprio bump de tag no `gitops/` ao mesmo tempo → `git push` rejeitado por não-fast-forward em quem perdesse a corrida. **Corrigido**: loop de retry (`git pull --rebase` + `git push`) de até 5 tentativas no step "Commit and push", nos 5 workflows.
   - A tag da imagem era só `v1.0.0-<sha>` — um `gh run rerun` no mesmo commit gera a mesma tag, e o repositório ECR tem *tag immutability* ligada (hardening da Fase 03), então o segundo push é rejeitado permanentemente para aquele commit. **Corrigido**: tag agora é `v1.0.0-<sha>-<run_attempt>`, nunca colide mesmo em reruns manuais.

Ambas as correções de CI foram validadas re-disparando os 5 pipelines simultaneamente (via commit que tocava os 5 arquivos de workflow) — todos passaram de ponta a ponta sem intervenção manual, confirmando que a race condition está genuinamente resolvida, não só contornada.

## Fase 1 — status (2026-11-15): Prometheus + Grafana + Alertmanager + Loki/Promtail no ar

Stack de observabilidade instalada via 2 Applications do ArgoCD (`kube-prometheus-stack`, `loki`), cada uma com fonte dupla (chart Helm upstream + arquivo de values neste repo) — `terraform/argocd-monitoring-apps.tf` + `gitops/monitoring/*.yaml`. Capacidade do cluster escalada de 2x t3.small → 3x t3.medium (ver `terraform/variables.tf`) para caber a stack nova.

**Cadeia de problemas reais encontrados e corrigidos (ótimo material para a seção de desafios do relatório):**

1. **Grafana com dois datasources `isDefault: true`** — `loki-stack` auto-registra Loki em QUALQUER Grafana do cluster via ConfigMap com label `grafana_datasource: "1"` (sidecar-discovered), já vindo com `isDefault: true` por padrão, colidindo com o datasource Prometheus do próprio `kube-prometheus-stack` (também `isDefault: true`). Grafana recusava subir. **Corrigido**: `loki.isDefault: false` em `loki-stack-values.yaml`.
2. **Grafana `OOMKilled`** — limite de 256Mi era insuficiente para o Grafana 13.3.1 (subsistema de busca/indexação "bleve-backend" mais pesado que versões antigas). **Corrigido**: limite subido para 512Mi.
3. **`etcdserver: request is too large` no ArgoCD** — `kube-prometheus-stack` com defaults renderiza ~126 recursos, incluindo 35 `PrometheusRule` e ~30 ConfigMaps de dashboards genéricos para componentes que o EKS gerenciado nem expõe (etcd, apiserver, scheduler, controller-manager — esses rodam dentro da AWS, inacessíveis). O status do Application (que lista cada recurso sincronizado) estourava o limite de ~1.5MB por objeto do etcd. **Corrigido**: `defaultRules.create: false`, `grafana.defaultDashboardsEnabled: false`, `kube{ApiServer,ControllerManager,Etcd,Scheduler}.enabled: false` — além de ser a correção certa, é a configuração correta para EKS (esses componentes nunca estariam disponíveis de qualquer forma). Resultado: 126 → 55 recursos.
4. **Mesmo erro, causa raiz diferente**: mesmo após reduzir os recursos, o erro persistia. Causa real: os CRDs `Prometheus` e `Alertmanager` do Prometheus Operator têm ~1MB cada (schema OpenAPI profundo) — `kubectl apply` client-side (usado internamente pelo ArgoCD) embute o manifesto inteiro de novo como anotação `last-applied-configuration`, estourando o limite rígido do Kubernetes de 256KB por anotação (`metadata.annotations: Too long`). **Corrigido definitivamente**: `syncOptions: ["ServerSideApply=true"]` nas duas Applications — Server-Side Apply não duplica o conteúdo como anotação.
5. **Operator do Prometheus não percebe CRDs novos** — o operator só verifica quais CRDs existem uma vez, na inicialização. Como os CRDs `Prometheus`/`Alertmanager`/`AlertmanagerConfig` não existiam quando o pod do operator subiu pela primeira vez, ele nunca reconciliava os recursos mesmo depois dos CRDs serem criados. **Corrigido**: reiniciar o pod do operator após os CRDs existirem (`kubectl delete pod`, o Deployment recria).
6. **Controller do próprio ArgoCD com estado interno travado** — mesmo com tudo corrigido, o controller ficava reemitindo o mesmo erro de etcd indefinidamente, descolado do campo `.operation` (já limpo). **Corrigido**: reiniciar o pod `argocd-application-controller-0` para forçar recarregar o estado persistido (pequeno, ~22KB) em vez de continuar com o estado em memória corrompido/inflado.

Acesso ao Grafana: `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80`, usuário `admin`, senha em `kubectl get secret kube-prometheus-stack-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d`.

**Dashboard customizado criado** (`gitops/monitoring/dashboards/togglemaster-overview-configmap.yaml`, uid `togglemaster-overview`, título "ToggleMaster — Ecosystem Health"), via uma 3ª Application do ArgoCD (`grafana-dashboards`, path simples em git, sem Helm) que aplica um ConfigMap com a label `grafana_dashboard: "1"` — descoberto automaticamente pelo sidecar do Grafana, sem precisar de restart. 4 painéis:
1. Uso de CPU por nó (%) — `node_cpu_seconds_total`.
2. Uso de memória por nó (%) — `node_memory_MemAvailable_bytes`/`MemTotal_bytes`.
3. **Taxa de tráfego por microsserviço** (bytes/s de rede, via `container_network_{receive,transmit}_bytes_total` do kubelet/cAdvisor) — usado como *proxy* de "taxa de requisições" enquanto os serviços não expõem métricas HTTP próprias. **Nota para o relatório/vídeo**: isto será substituído por uma taxa de requisições HTTP real assim que a Fase 2/3 (OTel Collector + instrumentação) estiver pronta — mesmo dashboard, painel atualizado.
4. Logs em tempo real (Loki) de todos os 5 namespaces de microsserviço.

Todas as 3 queries foram validadas com dados reais via a API do Prometheus antes de serem commitadas.

## Fase 2 — status (2026-11-16): OTel Collector no ar, Loki migrado para o chart atual

OTel Collector instalado via `open-telemetry/opentelemetry-collector` (imagem `contrib`), `mode: deployment`, Application `otel-collector` no ArgoCD. Pipelines: métricas → exporter `prometheus` (porta 8889, scraped via ServiceMonitor) → nosso Prometheus; logs → exporter `otlphttp` → ingestão OTLP nativa do Loki; traces → `debug` por enquanto (exporter do Datadog entra na Fase 3, quando existir uma API key real para configurar).

**Migração não-planejada, mas necessária: Loki `loki-stack` (2.6.1, deprecado) → `grafana/loki` standalone (7.6.0, app 3.6.11) + `grafana/promtail` (6.17.1) separado.** Causa raiz: o exporter dedicado `loki` foi **removido** das builds atuais do `otelcol-contrib` — o ecossistema Grafana migrou para ingestão OTLP nativa no Loki (só existe a partir da 3.0+), tornando aquele exporter obsoleto. Nosso Loki antigo (via loki-stack) estava preso na 2.6.1.

**Cadeia de problemas reais enfrentados nessa migração:**
1. **Colisão de nomes** entre o StatefulSet/Services antigos (loki-stack) e os novos (grafana/loki) — ambos usam o nome de release "loki". StatefulSets têm campos imutáveis (`volumeClaimTemplates`), então uma atualização in-place teria sido rejeitada. Resolvido apagando os recursos antigos antes de aplicar os novos.
2. **Cache de render do ArgoCD repo-server ficou stale** — mesmo com a Application corretamente configurada para o chart novo, o StatefulSet aplicado continuava com labels do chart antigo (`chart: loki-2.16.0`). Resolvido reiniciando o pod `argocd-repo-server`.
3. **PVC presa em `Pending`** — `storage class is set` ausente (sem StorageClass default no cluster) → corrigido especificando `gp2` explicitamente → só então descobrimos que **o cluster não tem o driver CSI do EBS instalado** (só tem EFS), e o provisionador antigo in-tree `kubernetes.io/aws-ebs` foi **removido do Kubernetes a partir da 1.27+** — não era questão de tempo, nenhum controlador no cluster conseguiria provisionar aquele volume. Resolvido desabilitando persistência (mesma escolha já feita para o Prometheus — armazenamento efêmero é aceitável nesta escala).
4. **Desabilitar persistência removeu o mount de `/var/loki` inteiramente** (não virou `emptyDir` automaticamente) — Loki falhava com `mkdir /var/loki: read-only file system`. Corrigido adicionando um `emptyDir` manual via `extraVolumes`/`extraVolumeMounts`.
5. **Memcached de cache (chunks/results)** do novo chart, habilitado por padrão, não conseguia ser agendado por falta de memória — desabilitado (`chunksCache.enabled: false`, `resultsCache.enabled: false`), overhead desnecessário no nosso volume de ingestão.
6. **Promtail travado após o período de instabilidade do Loki** — probe de readiness **sem resposta** (timeout, não apenas erro), sugerindo o processo preso, não só aguardando o Loki voltar. Resolvido reiniciando os pods.

Datasource do Loki no Grafana agora é provisionado manualmente (`gitops/monitoring/grafana-provisioning/datasources/loki-datasource-configmap.yaml`), já que o chart standalone não se auto-registra como o loki-stack fazia — mesmo mecanismo de sidecar discovery (`grafana_datasource: "1"`) usado para o dashboard customizado. A pasta foi reorganizada de `dashboards/` para `grafana-provisioning/{dashboards,datasources}/`, com a Application do ArgoCD usando `directory.recurse: true` para pegar as subpastas.

## Fase 3 — status (2026-11-16/17): Instrumentação APM completa nos 5 microsserviços

`evaluation-service` (Go) foi o primeiro, instrumentado manualmente (`otelhttp`, propagação W3C TraceContext), com verificação end-to-end completa: trace real de 3 spans (evaluation-service → flag-service + targeting-service) confirmado via kubectl e no Datadog APM (Flame Graph). A saga de versionamento de dependências Go (conflito entre `go mod tidy` e a versão de build do `golangci-lint`, mais uma CVE crítica real no `grpc`) ficou resolvida com pins exatos: `otel`/`sdk` v1.38.0, `otlptracegrpc` v1.32.0, `otelhttp` v0.59.0, `grpc` v1.80.0, diretiva `go 1.24.0`.

Com esses pins já validados, **auth-service** foi instrumentado reaproveitando exatamente os mesmos — CI passou de primeira em todos os 5 jobs, sem repetir a maratona de depuração.

Para os 3 serviços Python (**flag-service**, **targeting-service**, **analytics-service**), optou-se por auto-instrumentação via `opentelemetry-distro` em vez de instrumentação manual — **zero alterações no código da aplicação**. O wrapper `opentelemetry-instrument` faz monkey-patching das bibliotecas relevantes (Flask, requests, botocore) no nível do interpretador, antes do módulo da aplicação ser importado — basta prefixar o `CMD` do Dockerfile (`opentelemetry-instrument gunicorn ...`). Pacotes de instrumentação seguem o esquema de versão `0.66b2`-style — convenção permanente do projeto OTel Python para pacotes contrib/instrumentation, não sinal de instabilidade.

- **flag-service / targeting-service**: `opentelemetry-distro[otlp]` + `opentelemetry-instrumentation-flask` + `opentelemetry-instrumentation-requests`, todos `==0.66b2`.
- **analytics-service**: mesma base + `opentelemetry-instrumentation-botocore` no lugar de `-requests` (este serviço não chama outros serviços via HTTP, só SQS/DynamoDB via boto3). **Corte de escopo deliberado**: sem propagação manual de contexto de trace através do SQS (produtor `evaluation-service` → fila → este consumidor) — o desenho original não carrega contexto de trace em message attributes. O resultado são spans reais das chamadas SQS/DynamoDB em si (`receive_message`, `delete_message`, `put_item`), não um trace contínuo cruzando o limite assíncrono.

Mecanismo validado localmente antes do deploy (Docker indisponível na máquina local — smoke test rodado direto em venv Python 3.9, já que o runtime real do Dockerfile é 3.12): um app Flask mínimo sob `opentelemetry-instrument` produziu um span `GET /health` corretamente formatado via exporter de console. Confirmação final em produção: spans reais (`InstrumentationScope opentelemetry.instrumentation.flask 0.66b2`) capturados nos logs do próprio OTel Collector para os 4 serviços, gerados organicamente pelos readiness/liveness probes do Kubernetes — nenhum tráfego sintético precisou ser gerado.

**Variáveis de ambiente adicionadas** em `gitops/{service}/deployment.yaml` (auth/flag/targeting/analytics-service): `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4317`, `OTEL_EXPORTER_OTLP_PROTOCOL=grpc` (os dois últimos só nos 3 serviços Python — o Go lê o endpoint via env var própria com default embutido no código).

## Bug real encontrado e corrigido (2026-11-17): logs do Grafana vazios desde a migração do Loki

Usuário reportou que o painel de logs em tempo real do dashboard Grafana não mostrava nada. Investigação revelou que o Loki estava rejeitando **tanto leituras quanto escritas** desde a migração para o chart standalone na Fase 2 — erro real nos próprios logs do Loki: `"too many unhealthy instances in the ring"` (consultas) e `"at least 2 live replicas required, could only find 1"` (pushes do Promtail). Causa raiz: o chart `grafana/loki` usa `commonConfig.replication_factor: 3` por padrão, independente do `deploymentMode`, mas nosso `singleBinary.replicas` é `1` — o ring interno do Loki nunca atingia quórum. A verificação original da Fase 2 só checou saúde dos pods, nunca uma consulta de log de ponta a ponta, então o bug ficou invisível até agora.

**Corrigido** em `gitops/monitoring/loki-values.yaml`: adicionado `loki.commonConfig.replication_factor: 1`, consistente com nosso único replica. Verificado via ArgoCD hard-refresh + restart do pod `loki-0` + consulta direta à API do Loki (`/loki/api/v1/query_range`) confirmando que o erro desapareceu, seguido de uma requisição de teste real contra `evaluation-service` para gerar uma linha de log fresca e confirmar que ela chega ao Loki de ponta a ponta (apareceu em segundos, com o conteúdo exato esperado). Promtail já descobria e tentava fazer tail nos pods dos 5 microsserviços corretamente o tempo todo — não era um problema de descoberta, só de o Loki recusar o push.

**Estado final da Fase 3 (confirmado 2026-11-17)**: todos os 5 microsserviços instrumentados e confirmados emitindo spans reais, tanto via logs do OTel Collector quanto visualmente na UI do Datadog APM (aba Traces: 719 spans indexados, 0 erros, os 5 serviços listados na faceta "Service" com contagens reais — `analytics-service` 180, `auth-service` 135, `evaluation-service` 135, `targeting-service` 135, `flag-service` 134). A instrumentação `botocore` do analytics-service também captura a chamada de long-polling SQS em si (`ReceiveMessage SQS`, ~20.0s de duração — bate com o `WaitTimeSeconds=20` do código), com o Datadog inferindo a fila SQS como nó relacionado mesmo sem propagação de contexto cross-service. Requisito 3 (Instrumentação e APM) está **completo**. **Pendente**: checar a aba Service Map especificamente (view separada da lista de Traces) para confirmar o mapa de dependências entre os 5 serviços — ainda não verificado. Requisito 4 (Alertas Inteligentes e Self-Healing) permanece totalmente não iniciado.
