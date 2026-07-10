# ArgoCD + the per-env root Application (app-of-apps). Terraform's GitOps
# involvement ends here: after this, everything in gitops/ is ArgoCD's problem
# (ADR-0004). No ingress — access is `make argocd-ui` (port-forward); SSO is the
# documented hardening step (ADR-0013).

locals {
  system_scheduling = {
    nodeSelector = {
      "eksp.io/node-role" = "system"
    }
    tolerations = [{
      key      = "CriticalAddonsOnly"
      operator = "Exists"
      effect   = "NoSchedule"
    }]
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version

  values = [yamlencode({
    configs = {
      params = {
        # TLS terminates at the port-forward/ingress layer; the server itself
        # would otherwise self-sign and break the CLI.
        "server.insecure" = true
      }
    }

    controller = local.system_scheduling
    server     = merge(local.system_scheduling, { replicas = 1 })
    repoServer = merge(local.system_scheduling, { replicas = 1 })
    applicationSet = merge(local.system_scheduling, {
      enabled = true
    })
    redis = local.system_scheduling
    dex = {
      enabled = false # no SSO in v1 — see docs/SECURITY.md hardening list
    }
    notifications = {
      enabled = false
    }
  })]
}

resource "helm_release" "root_app" {
  count = var.repo_url != "" ? 1 : 0

  name       = "root-${var.env_name}"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version

  values = [yamlencode({
    applications = {
      "root-${var.env_name}" = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = var.repo_url
          targetRevision = var.target_revision
          path           = "gitops/envs/${var.env_name}/apps"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = {
            prune    = true
            selfHeal = true
          }
          syncOptions = ["ServerSideApply=true"]
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
