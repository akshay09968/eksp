output "state_bucket" {
  description = "S3 bucket holding Terraform state for all environments."
  value       = aws_s3_bucket.tf_state.bucket
}

output "plan_role_arn" {
  description = "Set as AWS_PLAN_ROLE_ARN repo variable — used by PR plan jobs."
  value       = aws_iam_role.github_plan.arn
}

output "apply_role_arn" {
  description = "Set as AWS_APPLY_ROLE_ARN repo variable — used by gated apply jobs."
  value       = aws_iam_role.github_apply.arn
}

output "ecr_push_role_arn" {
  description = "Set as AWS_ECR_PUSH_ROLE_ARN repo variable — used by image publish jobs."
  value       = aws_iam_role.github_ecr_push.arn
}

output "ecr_repository_urls" {
  description = "Registry URLs for application images."
  value       = { for name, repo in aws_ecr_repository.apps : name => repo.repository_url }
}
