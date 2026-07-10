output "alb_controller_role_arn" {
  description = "Pod Identity role used by the AWS Load Balancer Controller."
  value       = module.alb_controller_pod_identity.iam_role_arn
}
