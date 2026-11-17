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

## 7. Requirement 4 (Alerts / Self-Healing) — not yet built

_Placeholder — to be filled in once this phase is done: smart alert (e.g. auth-service 5xx rate), PagerDuty incident, Slack ChatOps notification, and a self-healing GitHub Action (webhook-triggered `kubectl rollout restart`) via Fase03's existing OIDC role._

## Diagram

_Placeholder — full end-to-end architecture diagram to be added once Requirement 4 is complete._
