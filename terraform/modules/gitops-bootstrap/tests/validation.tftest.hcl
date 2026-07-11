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
