# ToggleMaster — Fase 04

Tech Challenge Fase 04 (POSTECH) — observabilidade total e self-healing sobre a plataforma ToggleMaster.

Base herdada da [Fase 03](https://github.com/pedrohenriqueortizcosta-blip/togglemaster-fase03) (5 microsserviços, Terraform, CI/CD com DevSecOps, GitOps via ArgoCD). Esta fase adiciona, por cima dessa arquitetura:

- **Prometheus + Loki + Grafana** (via Helm charts no GitOps) — métricas e logs centralizados.
- **OTel Collector** — peça central de telemetria, roteando métricas/logs/traces para os backends corretos.
- **Datadog APM** — distributed tracing e Service Map dos 5 microsserviços.
- **Alertas → PagerDuty → Slack** — incidentes automáticos com notificação ChatOps.
- **Self-Healing** — GitHub Action disparada por webhook do Alertmanager, executando `kubectl rollout restart` sem intervenção humana.

Ver [`CLAUDE.md`](./CLAUDE.md) para o enunciado completo e o plano de execução.

Scripts de demonstração herdados da Fase 03 ficam em [`docs/fase03-reference/`](./docs/fase03-reference/) como referência histórica.
