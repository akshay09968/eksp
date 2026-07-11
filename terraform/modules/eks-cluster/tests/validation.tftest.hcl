# Input-contract tests. The upstream EKS + pod-identity modules are stubbed
# with override_module — their internals aren't under test here.

mock_provider "aws" {}

override_module {
  target = module.eks
  outputs = {
    cluster_name                       = "eksp-test"
    cluster_endpoint                   = "https://mock.eks.example"
    cluster_certificate_authority_data = "bW9jaw=="
    cluster_version                    = "1.33"
    node_security_group_id             = "sg-0123456789abcdef0"
    oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/mock"
  }
}

override_module {
  target  = module.ebs_csi_pod_identity
  outputs = {}
}

variables {
  name               = "eksp-test"
  vpc_id             = "vpc-0123456789abcdef0"
  private_subnet_ids = ["subnet-a", "subnet-b"]
  intra_subnet_ids   = ["subnet-c", "subnet-d"]
}

run "rejects_bogus_kubernetes_version" {
  command = plan

  variables {
    kubernetes_version = "2.1"
  }

  expect_failures = [var.kubernetes_version]
}

run "rejects_freeform_version_string" {
  command = plan

  variables {
    kubernetes_version = "latest"
  }

  expect_failures = [var.kubernetes_version]
}
