# Karpenter: controller IAM (Pod Identity), interruption queue, node role via the
# upstream submodule; controller via helm; NodePools/EC2NodeClass via a local chart
# so everything lands in one apply (ADR-0003, ADR-0004).

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = var.cluster_name

  namespace = var.namespace

  # Pod Identity (ADR-0005) — the submodule creates the association for us.
  create_pod_identity_association = true

  # Nodes need SSM for AL2023 access patterns (session manager debugging, no SSH).
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = var.tags
}

resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = var.namespace
  create_namespace = true

  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.chart_version

  wait = true

  values = [yamlencode({
    replicas = var.controller_replicas

    settings = {
      clusterName       = var.cluster_name
      interruptionQueue = module.karpenter.queue_name
    }

    serviceAccount = {
      name = module.karpenter.service_account
    }

    controller = {
      resources = {
        requests = {
          cpu    = var.controller_resources.cpu
          memory = var.controller_resources.memory
        }
        limits = {
          memory = var.controller_resources.memory
        }
      }
    }

    # Karpenter must run on capacity it does not manage — the tainted system MNG.
    nodeSelector = {
      "eksp.io/node-role" = "system"
    }

    tolerations = [{
      key      = "CriticalAddonsOnly"
      operator = "Exists"
      effect   = "NoSchedule"
    }]
  })]
}

resource "helm_release" "karpenter_resources" {
  name      = "karpenter-resources"
  namespace = var.namespace

  chart = "${path.module}/../../charts/karpenter-resources"

  values = [yamlencode({
    clusterName      = var.cluster_name
    nodeIamRoleName  = module.karpenter.node_iam_role_name
    cpuLimitSpot     = tostring(var.cpu_limit_spot)
    cpuLimitOnDemand = tostring(var.cpu_limit_on_demand)
    nodeVolumeSizeGi = var.node_volume_size_gi

    disruptionBudgets = var.disruption_budgets
  })]

  # CRDs (NodePool/EC2NodeClass) come with the controller chart.
  depends_on = [helm_release.karpenter]
}
