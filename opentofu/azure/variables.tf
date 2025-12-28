# Core infrastructure variables
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "silica"

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
  default     = "silica-network"
}

variable "azure_region" {
  description = "Azure region for infrastructure deployment"
  type        = string
  default     = "australiaeast" # Sydney
}

# Networking variables
variable "vnet_cidr" {
  description = "CIDR block for Virtual Network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["1", "2", "3"] # Azure uses zone numbers
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
    condition     = var.worker_node_count >= 0 && var.worker_node_count <= 100
    error_message = "Worker node count must be between 0 and 100."
  }
}

variable "regional_clusters" {
  description = <<-DESC
    Map of cluster identifiers to their region-specific configuration.
    If left empty, the legacy single-region variables (azure_region, vnet_cidr, etc.) will be used to create one cluster named "default".
  DESC
  type = map(object({
    azure_region         = string
    vnet_cidr            = string
    availability_zones   = list(string)
    validator_node_count = number
    worker_node_count    = number
  }))
  default = {}
}

variable "node_vm_size" {
  description = "VM size for nodes"
  type        = string
  default     = "Standard_D4s_v3" # 4 vCPUs, 16GB RAM
}

variable "system_node_vm_size" {
  description = "VM size for the system node pool"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "node_disk_size" {
  description = "Disk size in GB for each node"
  type        = number
  default     = 100

  validation {
    condition     = var.node_disk_size >= 20 && var.node_disk_size <= 1000
    error_message = "Node disk size must be between 20 and 1000 GB."
  }
}

variable "storage_type" {
  description = "Managed disk type"
  type        = string
  default     = "Premium_LRS"

  validation {
    condition     = contains(["Standard_LRS", "Premium_LRS", "StandardSSD_LRS", "PremiumV2_LRS"], var.storage_type)
    error_message = "Storage type must be one of: Standard_LRS, Premium_LRS, StandardSSD_LRS, PremiumV2_LRS."
  }
}

# Kubernetes configuration
variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.30"
}

# Security configuration
variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the infrastructure"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Restrict this in production
}

variable "enable_monitoring" {
  description = "Enable Azure Monitor integration"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable Azure Monitor logging"
  type        = bool
  default     = true
}

# Container configuration
variable "container_image" {
  description = "Container image for Silica nodes"
  type        = string
  default     = "ghcr.io/dedme/chert/silica:latest"
}

variable "container_cpu" {
  description = "CPU units for container (1 = 1 vCPU)"
  type        = number
  default     = 4
}

variable "container_memory" {
  description = "Memory in GB for container"
  type        = number
  default     = 16
}

# ============================================================================
# Web Services Configuration
# ============================================================================

# Storage Account variables
variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS" # Locally-redundant storage

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Static Web Apps variables
variable "static_web_app_location" {
  description = "Location for Static Web Apps (limited regions available)"
  type        = string
  default     = "East US 2" # Static Web Apps have specific regions

  validation {
    condition     = contains([
      "East US 2", "West US 2", "Central US", "West Europe", "East Asia"
    ], var.static_web_app_location)
    error_message = "Static Web Apps location must be one of the supported regions."
  }
}

variable "static_web_app_sku_tier" {
  description = "Static Web App SKU tier"
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard"], var.static_web_app_sku_tier)
    error_message = "Static Web App SKU tier must be Free or Standard."
  }
}

variable "static_web_app_sku_size" {
  description = "Static Web App SKU size"
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard"], var.static_web_app_sku_size)
    error_message = "Static Web App SKU size must be Free or Standard."
  }
}

variable "chert_custom_domain" {
  description = "Custom domain for Chert website (e.g., chert.coin). Leave empty to skip."
  type        = string
  default     = ""
}

variable "silica_custom_domain" {
  description = "Custom domain for Silica website (e.g., silica.network). Leave empty to skip."
  type        = string
  default     = ""
}

# Container Apps variables
variable "enable_container_apps" {
  description = "Enable Azure Container Apps environment for API hosting"
  type        = bool
  default     = false # Set to true when ready to deploy API
}

variable "api_container_image" {
  description = "Container image for Chert API service"
  type        = string
  default     = "ghcr.io/dedme/chert/api:latest"
}

# Front Door variables
variable "enable_front_door" {
  description = "Enable Azure Front Door for global CDN and routing"
  type        = bool
  default     = true
}

variable "front_door_sku_name" {
  description = "Azure Front Door SKU name"
  type        = string
  default     = "Standard_AzureFrontDoor"

  validation {
    condition     = contains(["Standard_AzureFrontDoor", "Premium_AzureFrontDoor"], var.front_door_sku_name)
    error_message = "Front Door SKU must be Standard_AzureFrontDoor or Premium_AzureFrontDoor."
  }
}

variable "enable_waf" {
  description = "Enable Web Application Firewall for Front Door"
  type        = bool
  default     = true
}

variable "waf_mode" {
  description = "WAF policy mode"
  type        = string
  default     = "Prevention"

  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "WAF mode must be Detection or Prevention."
  }
}

variable "waf_redirect_url" {
  description = "Redirect URL for WAF blocked requests"
  type        = string
  default     = "https://www.example.com/blocked"
}