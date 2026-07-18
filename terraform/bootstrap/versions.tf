terraform {
  # >= 1.10 for S3-native state locking (use_lockfile) used by the env roots.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "eksp"
      Component = "bootstrap"
      ManagedBy = "terraform"
    }
  }
}

# DR region for state-bucket replication (issue #18, state-replication.tf).
provider "aws" {
  alias  = "replica"
  region = var.state_replica_region

  default_tags {
    tags = {
      Project   = "eksp"
      Component = "bootstrap"
      ManagedBy = "terraform"
    }
  }
}
