# OpenTofu configuration for Chert network infrastructure
# This is the OpenTofu-compatible version of the original Terraform code

tofu {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "opentofu/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "opentofu/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "opentofu/helm"
      version = "~> 2.12"
    }
    random = {
      source  = "opentofu/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {
    # Backend configuration will be provided via backend config files
    # For security, avoid hardcoding bucket names and regions
  }
}

# AWS Provider configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "chert-blockchain"
      Environment = var.environment
      ManagedBy   = "opentofu"
      Network     = var.network_name
    }
  }
}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local variables for consistent naming
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Network     = var.network_name
    ManagedBy   = "opentofu"
  }
}