output "vpc_id" {
  description = "VPC id."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = var.vpc_cidr
}

output "private_subnet_ids" {
  description = "Private subnet ids (nodes + pods)."
  value       = module.vpc.private_subnets
}

output "private_subnet_cidrs" {
  description = "Private subnet CIDRs (one /18 per AZ)."
  value       = local.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet ids (ALBs, NAT)."
  value       = module.vpc.public_subnets
}

output "public_subnet_cidrs" {
  description = "Public subnet CIDRs (one /22 per AZ)."
  value       = local.public_subnets
}

output "intra_subnet_ids" {
  description = "Intra subnet ids (EKS control-plane ENIs; no internet route)."
  value       = module.vpc.intra_subnets
}

output "intra_subnet_cidrs" {
  description = "Intra subnet CIDRs (one /24 per AZ)."
  value       = local.intra_subnets
}

output "lb_access_log_bucket" {
  description = "S3 bucket for ALB/NLB access logs. Wire into LB annotations via scripts/configure-repo.sh."
  value       = aws_s3_bucket.lb_logs.bucket
}
