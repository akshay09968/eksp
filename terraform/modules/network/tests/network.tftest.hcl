# Offline unit tests for the subnet math and AZ handling (mocked AWS provider).
# Run: terraform -chdir=terraform/modules/network test

mock_provider "aws" {
  override_data {
    target = data.aws_availability_zones.available
    values = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
    }
  }
}

variables {
  name         = "eksp-test"
  cluster_name = "eksp-test"
  vpc_cidr     = "10.0.0.0/16"
}

run "three_az_layout" {
  command = plan

  variables {
    az_count = 3
  }

  assert {
    condition     = output.private_subnet_cidrs == tolist(["10.0.0.0/18", "10.0.64.0/18", "10.0.128.0/18"])
    error_message = "3-AZ private subnets must be the first three /18s of the /16."
  }

  assert {
    condition     = output.public_subnet_cidrs == tolist(["10.0.192.0/22", "10.0.196.0/22", "10.0.200.0/22"])
    error_message = "3-AZ public subnets must be /22s carved after the private /18s."
  }

  assert {
    condition     = output.intra_subnet_cidrs == tolist(["10.0.204.0/24", "10.0.205.0/24", "10.0.206.0/24"])
    error_message = "3-AZ intra subnets must be /24s carved after the public /22s."
  }
}

run "two_az_layout" {
  command = plan

  variables {
    az_count = 2
  }

  assert {
    condition     = length(output.private_subnet_cidrs) == 2 && length(output.public_subnet_cidrs) == 2 && length(output.intra_subnet_cidrs) == 2
    error_message = "2-AZ layout must produce exactly two subnets per tier."
  }
}

run "rejects_invalid_az_count" {
  command = plan

  variables {
    az_count = 4
  }

  expect_failures = [var.az_count]
}

run "rejects_non_16_cidr" {
  command = plan

  variables {
    az_count = 3
    vpc_cidr = "10.0.0.0/20"
  }

  expect_failures = [var.vpc_cidr]
}
