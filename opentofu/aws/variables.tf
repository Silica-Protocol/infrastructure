# Core infrastructure variables
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "chert"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, testnet, mainnet)"
  type        = string

  validation {
    condition     = contains(["dev", "testnet", "mainnet"], var.environment)
    error_message = "Environment must be one of: dev, testnet, mainnet."
  }
}

variable "network_name" {
  description = "Name of the blockchain network"
  type        = string
  default     = "silica"
}

variable "aws_region" {
  description = "AWS region for infrastructure deployment"
  type        = string
  default     = "us-west-2"
}

# Networking variables
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

# Node configuration
variable "validator_node_count" {
  description = "Number of validator nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.validator_node_count >= 1 && var.validator_node_count <= 100
    error_message = "Validator node count must be between 1 and 100."
  }
}

variable "worker_node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.worker_node_count >= 1 && var.worker_node_count <= 100
    error_message = "Worker node count must be between 1 and 100."
  }
}

variable "node_instance_type" {
  description = "EC2 instance type for nodes"
  type        = string
  default     = "t3.medium"
}

# Storage configuration
variable "node_storage_size" {
  description = "Storage size in GB for each node"
  type        = number
  default     = 100

  validation {
    condition     = var.node_storage_size >= 20 && var.node_storage_size <= 1000
    error_message = "Node storage size must be between 20 and 1000 GB."
  }
}

variable "storage_type" {
  description = "EBS volume type"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp3", "io1", "io2"], var.storage_type)
    error_message = "Storage type must be one of: gp3, io1, io2."
  }
}

# Security configuration
variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the infrastructure"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Restrict this in production
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable CloudWatch logging"
  type        = bool
  default     = true
}

# Secrets management
variable "secrets_manager_kms_key_id" {
  description = "KMS key ID for secrets encryption"
  type        = string
  default     = "alias/aws/secretsmanager"
}

# Container configuration
variable "container_image" {
  description = "Container image for Silica nodes"
  type        = string
  default     = "ghcr.io/dedme/chert/silica:latest"
}

variable "container_cpu" {
  description = "CPU units for container (1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "container_memory" {
  description = "Memory in MB for container"
  type        = number
  default     = 2048
}