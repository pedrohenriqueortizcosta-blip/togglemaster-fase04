# ToggleMaster

ToggleMaster is a feature-flag platform: it lets engineering teams turn features on or off for specific users, without a deploy, through percentage-based rollout rules and real-time evaluation.

This repository holds the current state of the platform — five microservices running on Kubernetes, provisioned entirely from code, deployed continuously, and now fully observable with automatic incident response.

## Architecture

| Service | Language | Datastore | Responsibility |
|---|---|---|---|
| `auth-service` | Go | PostgreSQL | Issues and validates API keys (stores only their SHA-256 hash) |
| `flag-service` | Python | PostgreSQL | CRUD for feature flag definitions |
| `targeting-service` | Python | PostgreSQL | Rollout rules (e.g. percentage-based targeting) tied to flags |
| `evaluation-service` | Go | Redis (cache) | Hot path — answers "is this flag on for this user?" in real time, caches results, emits evaluation events |
| `analytics-service` | Python | DynamoDB + SQS | Consumes evaluation events for historical analytics |

All external traffic enters through a single Nginx Ingress Controller, routed by path (`/auth`, `/flags`, `/targeting`, `/evaluate`, `/analytics`).

`evaluation-service` is the critical path: on a cache miss it fetches flag + targeting data concurrently, evaluates the rule (deterministic percentage rollout via `SHA1(userID+flagName) % 100`), caches the result, and fires an analytics event — all before returning.

## Infrastructure

Everything below is provisioned from code in [`terraform/`](./terraform) — no manual `kubectl apply`, no click-ops:

- **AWS EKS** — Kubernetes cluster running all five services
- **3× RDS PostgreSQL** — one per relational service
- **ElastiCache Redis** — evaluation cache
- **DynamoDB + SQS** — analytics event pipeline
- **ECR** — private image registry per service
- **IAM/IRSA** — least-privilege pod-level AWS access
- **GitHub OIDC federation** — CI/CD authenticates to AWS without long-lived credentials

## Delivery pipeline

- **CI/CD** — GitHub Actions ([`.github/workflows/`](./.github/workflows)) per service: build, lint, SAST/SCA security scanning, image build & push to ECR, GitOps manifest update.
- **GitOps** — [`gitops/`](./gitops) is the single source of truth for what's running in the cluster; ArgoCD continuously reconciles the cluster to match it.

## Observability & self-healing

Built on top of the architecture above:

- **Metrics & logs** — Prometheus and Loki, deployed via Helm charts managed through GitOps, with Grafana as the visualization layer (cluster resource usage, per-service request rate, live log search).
- **OpenTelemetry Collector** — the single telemetry ingestion point for every service; routes metrics, logs, and traces to their respective backends.
- **Distributed tracing / APM** — Datadog, instrumented via OpenTelemetry SDKs, providing end-to-end traces and a live service dependency map across all five services.
- **Alerting & incident response** — Grafana alert rules (e.g. elevated 5xx rate on `auth-service`) open a PagerDuty incident and notify an on-call Slack channel automatically.
- **Self-healing** — alerts trigger a GitHub Actions workflow via webhook, which authenticates to the cluster through the existing OIDC role and runs a targeted `kubectl rollout restart` to mitigate the failure without human intervention.

## Repository layout

```
auth-service/          targeting-service/     evaluation-service/
flag-service/          analytics-service/      (each: Dockerfile, source, README)
terraform/             # all AWS infrastructure, as code
gitops/                 # desired cluster state, reconciled by ArgoCD
.github/workflows/     # per-service CI/CD + DevSecOps pipelines
docs/                  # supporting reference material
```
