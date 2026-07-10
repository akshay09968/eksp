# bootstrap

The one Terraform root with **local state**: it creates the S3 state bucket every other
root stores state in (classic chicken-and-egg), plus the GitHub OIDC provider/roles and
the ECR repositories.

```bash
cd terraform/bootstrap
terraform init
terraform apply -var github_org=<you> -var github_repo=<repo>
```

Then:

1. Copy the three role ARNs from the outputs into GitHub repository **variables**
   (`AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN`, `AWS_ECR_PUSH_ROLE_ARN`). CI jobs
   no-op gracefully when these are unset.
2. Environments now init against the bucket: `make init ENV=dev` (the Makefile passes
   `-backend-config` computed from your account id — nothing to edit).

The local `terraform.tfstate` here is deliberately minimal (bucket + IAM + ECR).
Losing it is recoverable via `terraform import`; the resources are all named
deterministically. Do not add workload infrastructure to this root.
