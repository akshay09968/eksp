# The security-review contract: account-wide Route53 write access must be
# unrepresentable. Upstream pod-identity module stubbed via override_module.

mock_provider "aws" {}
mock_provider "helm" {}

override_module {
  target = module.alb_controller_pod_identity
  outputs = {
    iam_role_arn = "arn:aws:iam::123456789012:role/mock-alb"
  }
}

variables {
  cluster_name = "eksp-test"
  vpc_id       = "vpc-0123456789abcdef0"
  region       = "ap-south-1"
}

run "rejects_wildcard_zone_arns" {
  command = plan

  variables {
    route53_zone_arns = ["arn:aws:route53:::hostedzone/*"]
  }

  expect_failures = [var.route53_zone_arns]
}
