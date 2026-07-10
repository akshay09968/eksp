# Thin opinionated wrapper over terraform-aws-modules/eks v21 (ADR-0001).
#
# Opinions encoded here (see ADRs):
#   - Access entries API mode, never the aws-auth ConfigMap.
#   - KMS envelope encryption for Secrets (module default) + control-plane audit logs.
#   - VPC CNI prefix delegation ON (pod density + IP scale, ADR §SCALING) and the
#     eBPF network-policy agent ON.
#   - A small tainted Graviton "system" node group so cluster-critical components
#     never compete with workloads; everything else is Karpenter's job (ADR-0003).

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids
  control_plane_subnet_ids = var.intra_subnet_ids

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  access_entries = {
    for idx, arn in var.admin_principal_arns : "admin-${idx}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  enabled_log_types = ["api", "audit", "authenticator"]

  addons = {
    vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
        env = {
          # Prefix delegation: each ENI slot hands out a /28 (16 IPs) instead of a
          # single IP — the difference between ~29 and ~110+ pods per node, and the
          # lever that keeps IP allocation off the scale-out critical path.
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }

    eks-pod-identity-agent = {
      most_recent    = true
      before_compute = true
    }

    kube-proxy = {
      most_recent = true
    }

    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        autoScaling = {
          enabled     = true
          minReplicas = var.coredns_min_replicas
          maxReplicas = 10
        }
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { memory = "192Mi" }
        }
        tolerations = [{
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }]
        topologySpreadConstraints = [{
          maxSkew           = 1
          topologyKey       = "topology.kubernetes.io/zone"
          whenUnsatisfiable = "ScheduleAnyway"
          labelSelector = {
            matchLabels = { "k8s-app" = "kube-dns" }
          }
        }]
      })
    }

    aws-ebs-csi-driver = {
      most_recent = true
      configuration_values = jsonencode({
        controller = {
          tolerations = [{
            key      = "CriticalAddonsOnly"
            operator = "Exists"
            effect   = "NoSchedule"
          }]
        }
      })
    }

    metrics-server = {
      most_recent = true
      configuration_values = jsonencode({
        tolerations = [{
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }]
      })
    }
  }

  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_ARM_64_STANDARD"
      instance_types = var.system_node_instance_types
      subnet_ids     = var.private_subnet_ids

      min_size     = var.system_node_min
      max_size     = var.system_node_max
      desired_size = var.system_node_desired

      labels = {
        "eksp.io/node-role" = "system"
      }

      # Only components that explicitly tolerate this run here (CoreDNS, Karpenter,
      # ALB controller, ArgoCD). Workloads land on Karpenter capacity.
      taints = {
        critical = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  # Karpenter's EC2NodeClass discovers the node security group by this tag; it must
  # exist on exactly one SG per cluster.
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.name
  }

  tags = var.tags
}

# EBS CSI controller credentials via Pod Identity (ADR-0005) — role + association.
module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name = "${var.name}-ebs-csi"

  attach_aws_ebs_csi_policy = true

  associations = {
    controller = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }

  tags = var.tags
}
