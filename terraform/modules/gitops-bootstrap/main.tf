# ArgoCD + the per-env root Application (app-of-apps). Terraform's GitOps
# involvement ends here: after this, everything in gitops/ is ArgoCD's problem
# (ADR-0004). No ingress — access is `make argocd-ui` (port-forward); GitHub
# SSO is opt-in via github_sso_org (ADR-0019, RUNBOOK #github-sso).

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

  # --- GitHub SSO (ADR-0019): ArgoCD's bundled Dex with a github connector.
  # The $dex.github.* placeholders are resolved by ArgoCD from the argocd-secret
  # Secret at runtime — the operator patches those keys in out-of-band
  # (RUNBOOK #github-sso), so no OAuth credential ever enters Terraform state.
  sso_enabled = var.github_sso_org != ""

  argocd_cm = local.sso_enabled ? {
    url = var.argocd_url
    "dex.config" = yamlencode({
      connectors = [{
        type = "github"
        id   = "github"
        name = "GitHub"
        config = {
          clientID      = "$dex.github.clientId"
          clientSecret  = "$dex.github.clientSecret"
          orgs          = [{ name = var.github_sso_org }]
          teamNameField = "slug"
          useLoginAsID  = true
        }
      }]
    })
  } : {}

  # Org members are read-only; only the named team administers. Group claims
  # arrive as "org:team-slug" from the Dex github connector.
  argocd_rbac = local.sso_enabled ? {
    "policy.default" = "role:readonly"
    "policy.csv"     = "g, ${var.github_sso_org}:${var.github_sso_admin_team}, role:admin\n"
    scopes           = "[groups]"
  } : {}
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
      cm   = local.argocd_cm
      rbac = local.argocd_rbac
    }

    controller = local.system_scheduling
    server     = merge(local.system_scheduling, { replicas = 1 })
    repoServer = merge(local.system_scheduling, { replicas = 1 })
    applicationSet = merge(local.system_scheduling, {
      enabled = true
    })
    redis = local.system_scheduling
    # Bundled Dex comes up only when SSO is configured (ADR-0019); the local
    # admin account stays enabled as break-glass either way.
    dex = merge(local.system_scheduling, {
      enabled = local.sso_enabled
    })
    notifications = {
      enabled = false
    }
  })]

  lifecycle {
    precondition {
      condition     = !local.sso_enabled || var.github_sso_admin_team != ""
      error_message = "github_sso_org is set but github_sso_admin_team is empty — without a team→role:admin mapping every SSO user lands read-only and nobody can administer. Set the team slug (ADR-0019)."
    }
  }
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
