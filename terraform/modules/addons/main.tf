# Cluster-critical addons that carry AWS IAM coupling — the Terraform side of the
# ADR-0004 boundary. Everything without IAM lives in gitops/ under ArgoCD.

locals {
  system_scheduling = {
    nodeSelector = {
      "eksp.io/node-role" = "system"
    }
    tolerations = [{
      key      = "CriticalAddonsOnly"
      operator = "Exists"
      effect   = "NoSchedule"
    }]
  }
}

# ---------------------------------------------------------------------------
# AWS Load Balancer Controller — provisions ALBs/NLBs from Ingress/Service
# objects. IP target mode is the default (ADR-0006): ALB targets pods directly,
# skipping the NodePort/kube-proxy second hop.
# ---------------------------------------------------------------------------

module "alb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name = "${var.cluster_name}-alb-controller"

  attach_aws_lb_controller_policy = true

  associations = {
    controller = {
      cluster_name    = var.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }

  tags = var.tags
}

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.alb_controller_chart_version

  values = [yamlencode(merge(local.system_scheduling, {
    clusterName = var.cluster_name
    region      = var.region
    vpcId       = var.vpc_id

    replicaCount = 2

    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
    }

    defaultTargetType = "ip"
  }))]

  depends_on = [module.alb_controller_pod_identity]
}

# ---------------------------------------------------------------------------
# external-dns (optional — needs a Route53 zone). Off by default so the platform
# deploys in any account; the sample app is reachable via the raw ALB hostname.
# ---------------------------------------------------------------------------

module "external_dns_pod_identity" {
  count = var.enable_external_dns ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name = "${var.cluster_name}-external-dns"

  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = var.route53_zone_arns

  associations = {
    controller = {
      cluster_name    = var.cluster_name
      namespace       = "kube-system"
      service_account = "external-dns"
    }
  }

  tags = var.tags
}

resource "helm_release" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  name       = "external-dns"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = var.external_dns_chart_version

  lifecycle {
    precondition {
      condition     = length(var.route53_zone_arns) > 0 && length(var.domain_filters) > 0
      error_message = "enable_external_dns requires explicit route53_zone_arns and domain_filters — refusing account-wide DNS write access."
    }
  }

  values = [yamlencode(merge(local.system_scheduling, {
    provider = { name = "aws" }

    serviceAccount = {
      create = true
      name   = "external-dns"
    }

    domainFilters = var.domain_filters
    policy        = "upsert-only" # never delete records it didn't create
    txtOwnerId    = var.cluster_name
  }))]

  depends_on = [module.external_dns_pod_identity]
}

# ---------------------------------------------------------------------------
# cert-manager (optional — ACME via Route53 DNS-01).
# ---------------------------------------------------------------------------

module "cert_manager_pod_identity" {
  count = var.enable_cert_manager ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name = "${var.cluster_name}-cert-manager"

  attach_cert_manager_policy    = true
  cert_manager_hosted_zone_arns = var.route53_zone_arns

  associations = {
    controller = {
      cluster_name    = var.cluster_name
      namespace       = "cert-manager"
      service_account = "cert-manager"
    }
  }

  tags = var.tags
}

resource "helm_release" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0

  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_chart_version

  lifecycle {
    precondition {
      condition     = length(var.route53_zone_arns) > 0
      error_message = "enable_cert_manager requires explicit route53_zone_arns — refusing account-wide DNS write access."
    }
  }

  values = [yamlencode({
    crds = { enabled = true }

    serviceAccount = {
      name = "cert-manager"
    }
  })]

  depends_on = [module.cert_manager_pod_identity]
}
