# Terraform configuration for Chert network infrastructure
terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.27"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    random = {
      source  = "hashicorp/random"
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
      Project     = "silica-blockchain"
      Environment = var.environment
      ManagedBy   = "terraform"
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
    ManagedBy   = "terraform"
  }
}