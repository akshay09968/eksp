variable "name" {
  description = "Name prefix for the VPC and subnets (e.g. eksp-dev)."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name — stamped as the karpenter.sh/discovery subnet tag."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR. Must be /16 — the subnet layout carves 3x/18 private, 3x/22 public, 3x/24 intra out of it (see main.tf)."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr must be a valid /16 CIDR block."
  }
}

variable "az_count" {
  description = "Number of availability zones (2 for dev cost savings, 3 for HA)."
  type        = number
  default     = 3

  validation {
    condition     = contains([2, 3], var.az_count)
    error_message = "az_count must be 2 or 3."
  }
}

variable "enable_nat_per_az" {
  description = "One NAT gateway per AZ (prod: AZ-independent egress) vs a single shared NAT (dev: ~\\$33/mo each)."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "VPC flow logs to CloudWatch (14-day retention)."
  type        = bool
  default     = false
}

variable "interface_endpoints" {
  description = "Interface VPC endpoint services to create (e.g. [\"ecr.api\", \"ecr.dkr\", \"sts\"]). Each costs ~\\$7.3/mo/AZ but takes ECR pulls and STS off the NAT path. Gateway endpoints (S3, DynamoDB) are always created — they're free."
  type        = list(string)
  default     = []
}

variable "lb_access_log_retention_days" {
  description = "Days to keep ALB/NLB access logs in S3. These carry client IPs (personal data under GDPR) — bound the window (COMPLIANCE #4)."
  type        = number
  default     = 30
}

variable "elb_account_id" {
  description = "Regional ELB service account id for the access-log bucket policy (ALBs pre-2022 write as this principal). ap-south-1 = 718504428378; see AWS docs for other regions."
  type        = string
  default     = "718504428378"
}

variable "tags" {
  description = "Extra tags merged onto module-managed resources (provider default_tags cover the standard set)."
  type        = map(string)
  default     = {}
}
