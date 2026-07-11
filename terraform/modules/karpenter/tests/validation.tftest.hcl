# Input-contract tests. The upstream karpenter submodule is stubbed with
# override_module: its internals aren't under test here (mocked policy-document
# data sources produce invalid JSON and drown the expected failure otherwise).

mock_provider "aws" {}
mock_provider "helm" {}

override_module {
  target = module.karpenter
  outputs = {
    queue_name         = "mock-interruption-queue"
    service_account    = "karpenter"
    node_iam_role_name = "mock-node-role"
  }
}

variables {
  cluster_name = "eksp-test"
}

run "rejects_zero_spot_ceiling" {
  command = plan

  variables {
    cpu_limit_spot = 0
  }

  expect_failures = [var.cpu_limit_spot]
}

run "rejects_negative_fallback_ceiling" {
  command = plan

  variables {
    cpu_limit_on_demand = -5
  }

  expect_failures = [var.cpu_limit_on_demand]
}
