# Thin opinionated wrapper over terraform-aws-modules/vpc (ADR-0001).
#
# Subnet plan for a /16 (per AZ, sized for millions of requests — pods take the
# lion's share via VPC CNI prefix delegation):
#   private /18 → 16,382 usable IPs/AZ (nodes + pod prefixes)
#   public  /22 →  1,022 usable IPs/AZ (ALBs, NAT)
#   intra   /24 →    254 usable IPs/AZ (EKS control-plane ENIs, no internet route)

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # 9 carve-outs: 3x/18 (private), 3x/22 (public), 3x/24 (intra).
  cidrs           = cidrsubnets(var.vpc_cidr, 2, 2, 2, 6, 6, 6, 8, 8, 8)
  private_subnets = slice(local.cidrs, 0, var.az_count)
  public_subnets  = slice(local.cidrs, 3, 3 + var.az_count)
  intra_subnets   = slice(local.cidrs, 6, 6 + var.az_count)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets
  intra_subnets   = local.intra_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = !var.enable_nat_per_az
  one_nat_gateway_per_az = var.enable_nat_per_az

  enable_dns_hostnames    = true
  enable_dns_support      = true
  map_public_ip_on_launch = false

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    # Karpenter EC2NodeClass discovers subnets by this tag (ADR-0003).
    "karpenter.sh/discovery" = var.cluster_name
  }

  enable_flow_log                                 = var.enable_flow_logs
  create_flow_log_cloudwatch_log_group            = var.enable_flow_logs
  create_flow_log_cloudwatch_iam_role             = var.enable_flow_logs
  flow_log_cloudwatch_log_group_retention_in_days = 14
  flow_log_max_aggregation_interval               = 60

  tags = var.tags
}

# ---------------------------------------------------------------------------
# VPC endpoints. Gateway endpoints are free and always on; interface endpoints
# are opt-in per environment (each takes AWS-bound traffic off the NAT path —
# both a cost and a scale lever, see docs/COST.md and docs/SCALING.md).
# ---------------------------------------------------------------------------

resource "aws_security_group" "vpc_endpoints" {
  count = length(var.interface_endpoints) > 0 ? 1 : 0

  name_prefix = "${var.name}-vpce-"
  description = "Allow HTTPS to interface VPC endpoints from inside the VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.0"

  vpc_id = module.vpc.vpc_id

  endpoints = merge(
    {
      s3 = {
        service         = "s3"
        service_type    = "Gateway"
        route_table_ids = concat(module.vpc.private_route_table_ids, module.vpc.intra_route_table_ids)
        tags            = { Name = "${var.name}-s3" }
      }
      dynamodb = {
        service         = "dynamodb"
        service_type    = "Gateway"
        route_table_ids = module.vpc.private_route_table_ids
        tags            = { Name = "${var.name}-dynamodb" }
      }
    },
    {
      for svc in var.interface_endpoints : replace(svc, ".", "-") => {
        service             = svc
        service_type        = "Interface"
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
        private_dns_enabled = true
        tags                = { Name = "${var.name}-${replace(svc, ".", "-")}" }
      }
    }
  )

  tags = var.tags
}
