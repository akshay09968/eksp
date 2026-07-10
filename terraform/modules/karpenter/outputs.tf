output "node_iam_role_name" {
  description = "IAM role attached to Karpenter-launched nodes."
  value       = module.karpenter.node_iam_role_name
}

output "queue_name" {
  description = "SQS interruption queue consumed by the controller."
  value       = module.karpenter.queue_name
}
