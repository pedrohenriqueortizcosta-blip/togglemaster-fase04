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
        syncOptions = ["CreateNamespace=false"]
      }
    }
  }

  depends_on = [helm_release.argocd, kubernetes_namespace.monitoring]
}

resource "kubernetes_manifest" "argocd_app_loki_stack" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      # Helm release name = "loki" (matches the Application name), which is
      # what makes the Loki service resolve as plain "loki" in-cluster —
      # the datasource URL in kube-prometheus-stack-values.yaml depends on
      # this exact name.
      name      = "loki"
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }
    spec = {
      project = "default"

      sources = [
        {
          repoURL        = "https://grafana.github.io/helm-charts"
          chart          = "loki-stack"
          targetRevision = "2.10.3"
          helm = {
            valueFiles = ["$values/gitops/monitoring/loki-stack-values.yaml"]
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
        syncOptions = ["CreateNamespace=false"]
      }
    }
  }

  depends_on = [helm_release.argocd, kubernetes_namespace.monitoring]
}
