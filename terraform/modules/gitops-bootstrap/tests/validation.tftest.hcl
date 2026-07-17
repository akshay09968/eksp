# env_name drives the root Application's gitops path — an unknown env would
# sync nothing, silently.

mock_provider "helm" {}

run "rejects_unknown_environment" {
  command = plan

  variables {
    env_name = "qa"
  }

  expect_failures = [var.env_name]
}

# The OAuth callback base has to be a URL GitHub can redirect a browser to.
run "rejects_non_url_argocd_url" {
  command = plan

  variables {
    env_name   = "dev"
    argocd_url = "argocd.example.com"
  }

  expect_failures = [var.argocd_url]
}

# SSO with no admin team would leave every login read-only — nobody could
# administer ArgoCD (ADR-0019). The precondition must catch it at plan.
run "rejects_sso_org_without_admin_team" {
  command = plan

  variables {
    env_name       = "dev"
    github_sso_org = "example-org"
  }

  expect_failures = [helm_release.argocd]
}
