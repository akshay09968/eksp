variable "name" {
  description = "Cluster name (e.g. eksp-dev)."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.33"

  validation {
    condition     = can(regex("^1\\.(3[0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.3x."
  }
}

variable "vpc_id" {
  description = "VPC to place the cluster in."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for nodes."
  type        = list(string)
}

variable "intra_subnet_ids" {
  description = "Intra subnets for EKS control-plane ENIs."
  type        = list(string)
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Tighten to your IP/VPN in real deployments; private-only endpoint is the documented hardening step."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "system_node_instance_types" {
  description = "Instance types for the tainted system node group (Graviton)."
  type        = list(string)
  default     = ["t4g.medium"]
}

variable "system_node_min" {
  description = "System node group minimum size."
  type        = number
  default     = 2
}

variable "system_node_max" {
  description = "System node group maximum size."
  type        = number
  default     = 4
}

variable "system_node_desired" {
  description = "System node group desired size."
  type        = number
  default     = 2
}

variable "admin_principal_arns" {
  description = "Extra IAM principals granted cluster-admin via access entries (the cluster creator is admin automatically)."
  type        = list(string)
  default     = []
}

variable "coredns_min_replicas" {
  description = "CoreDNS autoscaling floor. DNS is the classic high-RPS failure mode — never let it scale to 1."
  type        = number
  default     = 2
}

variable "tags" {
  description = "Extra tags merged onto module-managed resources."
  type        = map(string)
  default     = {}
}
