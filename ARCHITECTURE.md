# ToggleMaster — Fase 04 Architecture Overview

> Living summary of what's actually built and running, layer by layer. Written for quick recall and as source material for the report/video — not a replacement for `CLAUDE.md`, which has the full phase-by-phase history (including every bug hit and fixed along the way).

## 1. Infrastructure (AWS, via Terraform)

- **EKS cluster** `togglemaster` — 3x `t3.medium` worker nodes (scaled up from Fase03's 2x `t3.small` to fit the observability stack), managed via a Terraform module with a zero-downtime node-group-replacement pattern (`create_before_destroy` + name prefix).
- **RDS** (Postgres) and **ElastiCache**, carried over from Fase03.
- **SQS queue** (`togglemaster-evaluation-service`) and a **DynamoDB table** (`ToggleMasterAnalytics`) for the async analytics pipeline.
- **ECR** repositories per service, immutable tags.
- Terraform state intentionally shared with Fase03's S3 backend key — this repo (`togglemaster-fase04`) is the only one allowed to `apply` now; Fase03 is treated as frozen/archived.

## 2. GitOps / CI/CD

- **GitHub Actions** (5 separate workflows, one per service): lint → security scan (SAST+SCA via Trivy) → build/test → Docker build+push to ECR → bump the image tag in this repo's `gitops/` manifests.
- **ArgoCD**, watching this repo's `gitops/` folder, auto-syncs every change to the cluster. Nothing gets `kubectl apply`'d by hand — every Terraform-managed `Application` resource points at either a Helm chart + values file (monitoring stack) or a plain directory of manifests (the 5 microservices).
- CI→AWS auth is via GitHub OIDC (no static AWS keys in GitHub), reusing Fase03's IAM role.

## 3. The 5 microservices

```
auth-service (Go)          — API key validation against Postgres
flag-service (Python)      — feature flag CRUD, calls auth-service to validate
targeting-service (Python) — targeting rules CRUD, calls auth-service to validate
evaluation-service (Go)    — evaluates a flag for a user: calls flag-service +
                              targeting-service, caches in Redis, then
                              publishes an async event to SQS
analytics-service (Python) — background worker consuming that SQS queue,
                              writes each event into DynamoDB; also exposes
                              a trivial /health endpoint
```

Each has its own namespace, its own GitOps-managed Deployment, and its own OTel instrumentation (see §6).

## 4. Observability data plane (Prometheus / Loki / Grafana)

- **kube-prometheus-stack** — Prometheus scrapes infra + pod metrics cluster-wide (trimmed from its ~126-resource default to ~55; several default monitors target EKS control-plane components AWS doesn't expose).
- **Loki** (standalone `grafana/loki` chart, migrated off the deprecated `loki-stack`) — central log store, ephemeral storage (no EBS CSI driver in this cluster).
- **Promtail** — DaemonSet shipping every container's stdout/stderr into Loki.
- **Grafana** — single pane of glass. Custom dashboard "ToggleMaster — Ecosystem Health", 4 panels: cluster CPU%, cluster memory%, per-service network I/O (request-rate proxy), live Loki logs across all 5 service namespaces.

> **Bug fixed 2026-11-17**: the logs panel was empty because Loki's internal ring never reached quorum — the `grafana/loki` chart defaults `commonConfig.replication_factor` to 3 regardless of `deploymentMode`, but we only run 1 `singleBinary` replica. This silently rejected both reads *and* Promtail's writes since the Phase 2 migration (`"at least 2 live replicas required, could only find 1"`). Fixed by setting `loki.commonConfig.replication_factor: 1` in `loki-values.yaml`. Verified end-to-end with a fresh test request, confirming a log line reached Loki within seconds of the fix.

## 5. OTel Collector — the central routing piece

The mandatory piece tying the microservices to both the open-source stack and the commercial APM:

```
                    ┌──────────────┐
  metrics  ───────▶ │              │ ───▶ Prometheus ("prometheus" exporter,
                    │     OTel     │       scraped)
  logs     ───────▶ │  Collector   │ ───▶ Loki ("otlphttp", native OTLP
                    │  (contrib)   │       ingestion)
  traces   ───────▶ │              │ ───▶ Datadog ("datadog" exporter,
                    └──────────────┘       site ap2.datadoghq.com)
```

All 5 microservices send traces here over OTLP/gRPC — none talk to Datadog directly.

## 6. APM instrumentation (Datadog) — Requirement 3, complete

- `evaluation-service` / `auth-service` (Go): manually instrumented with `otelhttp`, wrapping every HTTP handler + outgoing client call.
- `flag-service` / `targeting-service` / `analytics-service` (Python): zero application code changes — the `opentelemetry-instrument` wrapper auto-patches Flask/requests/botocore at the interpreter level, prefixed onto each Dockerfile's `CMD`.
- Confirmed live in Datadog: all 5 services show up in Traces (700+ indexed spans), `evaluation-service`'s Dependencies page shows real arrows to `flag-service` and `targeting-service`, `analytics-service`'s Dependencies page shows its AWS-side calls (`sts`, the SQS queue) via the `botocore` instrumentor.
- `analytics-service`'s DynamoDB `PutItem` write is confirmed at the application-log level (real, successful write), though catching that specific span in Datadog's UI is subject to trial-account trace sampling — a single one-off event has real odds of not being the one randomly retained, unlike the continuously-repeating `ReceiveMessage` calls.

## 7. Requirement 4 (Alerts / Self-Healing) — complete

```
  Prometheus                 Alertmanager                 self-healing-dispatcher
┌──────────────┐  alert    ┌──────────────┐   webhook    ┌──────────────────────┐
│ auth-service  │ ───────▶ │  routes to:  │ ───────────▶ │ translates to a real  │
│ 5xx rate > 5% │  fires   │ 3 receivers  │   (parallel) │ repository_dispatch   │
└──────────────┘           │ in parallel: │              │ call via GitHub's API │
                           └──────┬───────┘              └───────────┬──────────┘
                     ┌────────────┼────────────┐                     │
                     ▼            ▼            ▼                     ▼
               ┌──────────┐ ┌──────────┐ ┌───────────┐     ┌────────────────────┐
               │PagerDuty │ │  Slack   │ │(dispatcher│     │ GitHub Action       │
               │ incident │ │ #alerts  │ │  webhook) │     │ "Self-Healing"      │
               └──────────┘ └──────────┘ └───────────┘     │ (repository_dispatch│
                                                            │  trigger)           │
                                                            │                     │
                                                            │ assumes existing    │
                                                            │ OIDC role (same one │
                                                            │ every CI pipeline   │
                                                            │ uses) → now also    │
                                                            │ granted:            │
                                                            │ - eks:DescribeCluster│
                                                            │   (IAM)             │
                                                            │ - get/list/watch/   │
                                                            │   patch Deployments │
                                                            │   (K8s RBAC, scoped │
                                                            │   to auth-service   │
                                                            │   namespace only)   │
                                                            │                     │
                                                            │ runs:               │
                                                            │ kubectl rollout     │
                                                            │ restart deployment/ │
                                                            │ auth-service        │
                                                            └─────────────────────┘
```

The alert rule's metric (`http_server_duration_milliseconds_count`) comes from `auth-service`'s own `otelhttp` instrumentation (same OTLP pipeline as Phase 3's traces), routed through the OTel Collector to Prometheus.

**Real bug found while building this**: the OTel Collector's `ServiceMonitor` had been missing the `release: kube-prometheus-stack` label Prometheus's `serviceMonitorSelector` requires — meaning Prometheus had *never* actually scraped any app-level metric through the Collector, since Phase 2. This was silent (no errors anywhere) until this alert's query was tested against real data. Fixed via `serviceMonitor.extraLabels` in `otel-collector-values.yaml`. Full bug list (6 total, including an IAM permission gap and a Prometheus label-collision rename) is in `CLAUDE.md`'s "Requisito 4" section.

**Verified end-to-end with a real, deliberately-induced failure**: `auth-service`'s dedicated RDS instance was stopped (each service has its own instance — confirmed via Terraform, so this had zero blast radius on `flag-service`/`targeting-service`), driving its 5xx rate to 48.6% against real test traffic. The alert fired, PagerDuty opened a real incident, Slack posted to `#alerts`, the dispatcher fired a real `repository_dispatch`, and the GitHub Action ran a genuine `kubectl rollout restart` — confirmed via `deployment.apps/auth-service restarted` in the Action's own logs, and the pod's restart count in `kubectl get pods`.
