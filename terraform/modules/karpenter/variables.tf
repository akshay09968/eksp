variable "cluster_name" {
  description = "EKS cluster name Karpenter manages."
  type        = string
}

variable "chart_version" {
  description = "Karpenter helm chart version (oci://public.ecr.aws/karpenter/karpenter)."
  type        = string
  # renovate: datasource=docker depName=public.ecr.aws/karpenter/karpenter
  default = "1.13.0"
}

variable "namespace" {
  description = "Namespace for the Karpenter controller."
  type        = string
  default     = "karpenter"
}

variable "controller_replicas" {
  description = "Controller replicas (2 gives leader-elected HA across system nodes)."
  type        = number
  default     = 2
}

variable "controller_resources" {
  description = "Controller pod resources — sized down for dev system nodes, up for prod."
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "250m"
    memory = "512Mi"
  }
}

variable "cpu_limit_spot" {
  description = "Aggregate vCPU ceiling for the spot pool (blast-radius guard)."
  type        = number
  default     = 500

  validation {
    condition     = var.cpu_limit_spot > 0
    error_message = "cpu_limit_spot must be positive — a zero ceiling means Karpenter can never provision."
  }
}

variable "cpu_limit_on_demand" {
  description = "Aggregate vCPU ceiling for the on-demand fallback pool."
  type        = number
  default     = 100

  validation {
    condition     = var.cpu_limit_on_demand > 0
    error_message = "cpu_limit_on_demand must be positive — the fallback pool is the spot-crunch escape hatch."
  }
}

variable "node_volume_size_gi" {
  description = "Root volume size for Karpenter-launched nodes (Gi)."
  type        = number
  default     = 50
}

variable "ami_alias" {
  description = "EC2NodeClass amiSelectorTerms alias. al2023@latest lets every AMI release roll nodes at Karpenter's discretion — fine for dev; staging/prod pin a dated release (al2023@vYYYYMMDD) so AMI rollouts arrive as reviewable PRs (issue #15)."
  type        = string
  default     = "al2023@latest"

  validation {
    condition     = can(regex("^al2023@(latest|v[0-9]{8})$", var.ami_alias))
    error_message = "ami_alias must be al2023@latest or a dated release like al2023@v20260709 (see awslabs/amazon-eks-ami releases)."
  }
}

variable "disruption_budgets" {
  description = "Karpenter disruption budgets. Default: at most 10% of nodes at once; prod adds a business-hours freeze."
  type        = list(map(string))
  default     = [{ nodes = "10%" }]
}

variable "tags" {
  description = "Extra tags for AWS resources (SQS queue, IAM)."
  type        = map(string)
  default     = {}
}
