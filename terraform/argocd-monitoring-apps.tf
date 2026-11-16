# ---------------------------------------------------------------------------
# Observability stack (Prometheus + Grafana + Alertmanager + Loki/Promtail),
# installed via ArgoCD the same way as the 5 microservices — but each
# Application here has TWO sources instead of one:
#
#   1. the real upstream Helm chart (fetched from its own chart repo,
#      pinned to an exact version)
#   2. this same git repo, for just the values file we wrote ourselves
#      (gitops/monitoring/*-values.yaml)
#
# ArgoCD merges them (chart templates + our values) and keeps the result
# continuously synced — same self-heal behavior as everything else.
# ---------------------------------------------------------------------------

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "kubernetes_manifest" "argocd_app_kube_prometheus_stack" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "kube-prometheus-stack"
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }
    spec = {
      project = "default"

      sources = [
        {
          repoURL        = "https://prometheus-community.github.io/helm-charts"
          chart          = "kube-prometheus-stack"
          targetRevision = "93.3.0"
          helm = {
            valueFiles = ["$values/gitops/monitoring/kube-prometheus-stack-values.yaml"]
          }
        },
        {
          repoURL        = "https://github.com/${var.github_repository}.git"
          targetRevision = "main"
          ref            = "values"
        },
      ]

      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = kubernetes_namespace.monitoring.metadata[0].name
      }

      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        # ServerSideApply: this chart's CRDs (Prometheus, Alertmanager,
        # AlertmanagerConfig) are each ~1MB — client-side apply embeds the
        # whole object a SECOND time as a "last-applied-configuration"
        # annotation, which blows past Kubernetes' hard 256KB-per-annotation
        # limit ("metadata.annotations: Too long"). Server-side apply skips
        # that duplication entirely.
        syncOptions = ["CreateNamespace=false", "ServerSideApply=true"]
      }
    }
  }

  depends_on = [helm_release.argocd, kubernetes_namespace.monitoring]
}

resource "kubernetes_manifest" "argocd_app_otel_collector" {
  # Mandatory central telemetry piece (requirement 2): receives OTLP
  # metrics/logs/traces from the 5 microservices (once instrumented in
  # Phase 3) and routes each to the right backend — see
  # gitops/monitoring/otel-collector-values.yaml for the pipeline config.
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "otel-collector"
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }
    spec = {
      project = "default"

      sources = [
        {
          repoURL        = "https://open-telemetry.github.io/opentelemetry-helm-charts"
          chart          = "opentelemetry-collector"
          targetRevision = "0.178.3"
          helm = {
            valueFiles = ["$values/gitops/monitoring/otel-collector-values.yaml"]
          }
        },
        {
          repoURL        = "https://github.com/${var.github_repository}.git"
          targetRevision = "main"
          ref            = "values"
        },
      ]

      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = kubernetes_namespace.monitoring.metadata[0].name
      }

      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=false", "ServerSideApply=true"]
      }
    }
  }

  depends_on = [helm_release.argocd, kubernetes_namespace.monitoring]
}

resource "kubernetes_manifest" "argocd_app_grafana_provisioning" {
  # Plain git-path Application (no Helm chart involved) — same pattern as
  # the 5 microservices' own Applications in argocd-apps.tf. Applies
  # whatever ConfigMaps live under gitops/monitoring/grafana-provisioning/
  # (dashboards/ and datasources/ subfolders); Grafana's own sidecar
  # (enabled by default in kube-prometheus-stack) discovers ConfigMaps
  # labeled "grafana_dashboard: 1" or "grafana_datasource: 1" and loads
  # them automatically — no restart needed when something's added here.
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "grafana-provisioning"
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }
    spec = {
      project = "default"

      source = {
        repoURL        = "https://github.com/${var.github_repository}.git"
        targetRevision = "main"
        path           = "gitops/monitoring/grafana-provisioning"
        directory = {
          # ArgoCD's directory source only reads the top level by default —
          # without this, the dashboards/ and datasources/ subfolders here
          # would be silently ignored.
          recurse = true
        }
      }

      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = kubernetes_namespace.monitoring.metadata[0].name
      }

      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=false"]
      }
    }
  }

  depends_on = [helm_release.argocd, kubernetes_namespace.monitoring]
}

resource "kubernetes_manifest" "argocd_app_loki" {
  # Standalone grafana/loki chart — replaces the deprecated loki-stack
  # bundle (see loki-values.yaml for why). Release/Application name "loki"
  # is deliberately kept, so the Service still resolves as plain
  # "loki.monitoring.svc.cluster.local" — nothing downstream (the Grafana
  # datasource, Promtail's client, the OTel Collector's exporter) needed to
  # change because of this migration, only loki-stack -> loki + promtail.
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "loki"
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }
    spec = {
      project = "default"

      sources = [
        {
          repoURL        = "https://grafana.github.io/helm-charts"
          chart          = "loki"
          targetRevision = "7.6.0"
          helm = {
            valueFiles = ["$values/gitops/monitoring/loki-values.yaml"]
          }
        },
        {
          repoURL        = "https://github.com/${var.github_repository}.git"
          targetRevision = "main"
          ref            = "values"
        },
      ]

      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = kubernetes_namespace.monitoring.metadata[0].name
      }

      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=false", "ServerSideApply=true"]
      }
    }
  }

  depends_on = [helm_release.argocd, kubernetes_namespace.monitoring]
}

resource "kubernetes_manifest" "argocd_app_promtail" {
  # Standalone grafana/promtail chart — the log-shipping half of what
  # loki-stack used to bundle together with Loki itself.
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "promtail"
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }
    spec = {
      project = "default"

      sources = [
        {
          repoURL        = "https://grafana.github.io/helm-charts"
          chart          = "promtail"
          targetRevision = "6.17.1"
          helm = {
            valueFiles = ["$values/gitops/monitoring/promtail-values.yaml"]
          }
        },
        {
          repoURL        = "https://github.com/${var.github_repository}.git"
          targetRevision = "main"
          ref            = "values"
        },
      ]

      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = kubernetes_namespace.monitoring.metadata[0].name
      }

      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=false", "ServerSideApply=true"]
      }
    }
  }

  depends_on = [helm_release.argocd, kubernetes_namespace.monitoring]
}
