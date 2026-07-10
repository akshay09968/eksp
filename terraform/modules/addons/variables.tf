variable "cluster_name" {
  description = "Target EKS cluster."
  type        = string
}

variable "vpc_id" {
  description = "VPC id (ALB controller needs it for subnet discovery)."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "alb_controller_chart_version" {
  description = "aws-load-balancer-controller chart version."
  type        = string
  # renovate: datasource=helm depName=aws-load-balancer-controller registryUrl=https://aws.github.io/eks-charts
  default = "3.4.1"
}

variable "enable_external_dns" {
  description = "Install external-dns (requires a Route53 hosted zone you own)."
  type        = bool
  default     = false
}

variable "external_dns_chart_version" {
  description = "external-dns chart version."
  type        = string
  # renovate: datasource=helm depName=external-dns registryUrl=https://kubernetes-sigs.github.io/external-dns/
  default = "1.21.1"
}

variable "domain_filters" {
  description = "Domains external-dns is allowed to manage (empty = all zones in the account — set this)."
  type        = list(string)
  default     = []
}

variable "route53_zone_arns" {
  description = "Hosted zone ARNs external-dns/cert-manager may write to."
  type        = list(string)
  default     = ["arn:aws:route53:::hostedzone/*"]
}

variable "enable_cert_manager" {
  description = "Install cert-manager (Route53 DNS-01 for ACME certs)."
  type        = bool
  default     = false
}

variable "cert_manager_chart_version" {
  description = "cert-manager chart version."
  type        = string
  # renovate: datasource=helm depName=cert-manager registryUrl=https://charts.jetstack.io
  default = "v1.21.0"
}

variable "tags" {
  description = "Extra tags for AWS resources."
  type        = map(string)
  default     = {}
}
