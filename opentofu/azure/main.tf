# OpenTofu configuration for Silica network infrastructure on Azure
# This configuration now supports deploying multiple regional clusters in one apply

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
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

  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "silicaterraformstate"
    container_name       = "tfstate"
    key                  = "azure.terraform.tfstate"
  }
}

# Azure Provider configuration
provider "azurerm" {
  features {}
}

# Random suffix for unique resource naming (shared by global web resources)
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

  # Derive an effective set of clusters. If no regional map is provided, fall back to legacy single-cluster variables.
  effective_clusters = length(var.regional_clusters) > 0 ? var.regional_clusters : {
    default = {
      azure_region          = var.azure_region
      vnet_cidr             = var.vnet_cidr
      availability_zones    = var.availability_zones
      validator_node_count  = var.validator_node_count
      worker_node_count     = var.worker_node_count
    }
  }

  cluster_short_base = {
    for cluster_key in keys(local.effective_clusters) :
    cluster_key => lower(substr(replace(cluster_key, "_", ""), 0, 8))
  }

  cluster_short_label = {
    for cluster_key in keys(local.effective_clusters) :
    cluster_key => "${local.cluster_short_base[cluster_key]}-${substr(sha1(cluster_key), 0, 4)}"
  }

  cluster_name_prefix = {
    for cluster_key, cfg in local.effective_clusters :
    cluster_key => "${var.project_name}-${var.environment}-${local.cluster_short_label[cluster_key]}"
  }

  cluster_dns_label = {
    for cluster_key in keys(local.effective_clusters) :
    cluster_key => replace(local.cluster_name_prefix[cluster_key], "_", "-")
  }

  cluster_node_resource_group = {
    for cluster_key in keys(local.effective_clusters) :
    cluster_key => substr(
      "${substr(var.project_name, 0, 3)}-${substr(var.environment, 0, 2)}-${local.cluster_short_label[cluster_key]}-mc",
      0,
      40
    )
  }

  cluster_tags = {
    for cluster_key, cfg in local.effective_clusters :
    cluster_key => merge(local.common_tags, {
      Cluster = cluster_key
      Region  = cfg.azure_region
    })
  }

  primary_cluster_key = tolist(keys(local.effective_clusters))[0]

  cluster_subnet_count = {
    for cluster_key, cfg in local.effective_clusters :
    cluster_key => max(1, min(length(cfg.availability_zones), 3))
  }

  public_subnet_definitions = {
    for entry in flatten([
      for cluster_key, cfg in local.effective_clusters : [
        for subnet_index in range(local.cluster_subnet_count[cluster_key]) : {
          key         = "${cluster_key}-public-${subnet_index}"
          cluster_key = cluster_key
          index       = subnet_index
        }
      ]
    ]) :
    entry.key => {
      cluster_key = entry.cluster_key
      index       = entry.index
    }
  }

  private_subnet_definitions = {
    for entry in flatten([
      for cluster_key, cfg in local.effective_clusters : [
        for subnet_index in range(local.cluster_subnet_count[cluster_key]) : {
          key         = "${cluster_key}-private-${subnet_index}"
          cluster_key = cluster_key
          index       = subnet_index
        }
      ]
    ]) :
    entry.key => {
      cluster_key = entry.cluster_key
      index       = entry.index
    }
  }

  worker_subnet_index = {
    for cluster_key, count in local.cluster_subnet_count :
    cluster_key => (count > 1 ? 1 : 0)
  }

  cluster_order = {
    for index, cluster_key in tolist(keys(local.effective_clusters)) :
    cluster_key => index
  }

  cluster_service_cidr = {
    for cluster_key, order in local.cluster_order :
    cluster_key => cidrsubnet("10.200.0.0/16", 4, order)
  }

  cluster_dns_service_ip = {
    for cluster_key in keys(local.effective_clusters) :
    cluster_key => cidrhost(local.cluster_service_cidr[cluster_key], 10)
  }

  validator_disk_definitions = {
    for definition in flatten([
      for cluster_key, cfg in local.effective_clusters : [
        for disk_index in range(cfg.validator_node_count) : {
          key         = "${cluster_key}-validator-${disk_index}"
          cluster_key = cluster_key
          index       = disk_index
        }
      ]
    ]) :
    definition.key => definition
  }

  worker_disk_definitions = {
    for definition in flatten([
      for cluster_key, cfg in local.effective_clusters : [
        for disk_index in range(cfg.worker_node_count) : {
          key         = "${cluster_key}-worker-${disk_index}"
          cluster_key = cluster_key
          index       = disk_index
        }
      ]
    ]) :
    definition.key => definition
  }
}

# ----------------------------------------------------------------------------
# Core network + compute per cluster
# ----------------------------------------------------------------------------

resource "azurerm_resource_group" "main" {
  for_each = local.effective_clusters

  name     = "${local.cluster_name_prefix[each.key]}-rg"
  location = each.value.azure_region
  tags     = local.cluster_tags[each.key]
}

resource "azurerm_virtual_network" "main" {
  for_each = local.effective_clusters

  name                = "${local.cluster_name_prefix[each.key]}-vnet"
  address_space       = [each.value.vnet_cidr]
  location            = azurerm_resource_group.main[each.key].location
  resource_group_name = azurerm_resource_group.main[each.key].name
  tags                = local.cluster_tags[each.key]
}

resource "azurerm_subnet" "public" {
  for_each = local.public_subnet_definitions

  name                 = "${local.cluster_name_prefix[each.value.cluster_key]}-public-${each.value.index + 1}"
  resource_group_name  = azurerm_resource_group.main[each.value.cluster_key].name
  virtual_network_name = azurerm_virtual_network.main[each.value.cluster_key].name
  address_prefixes     = [cidrsubnet(local.effective_clusters[each.value.cluster_key].vnet_cidr, 8, each.value.index)]
}

resource "azurerm_subnet" "private" {
  for_each = local.private_subnet_definitions

  name                 = "${local.cluster_name_prefix[each.value.cluster_key]}-private-${each.value.index + 1}"
  resource_group_name  = azurerm_resource_group.main[each.value.cluster_key].name
  virtual_network_name = azurerm_virtual_network.main[each.value.cluster_key].name
  address_prefixes     = [cidrsubnet(local.effective_clusters[each.value.cluster_key].vnet_cidr, 8, each.value.index + 10)]
}

resource "azurerm_public_ip" "nat" {
  for_each = local.effective_clusters

  name                = "${local.cluster_name_prefix[each.key]}-nat-pip"
  resource_group_name = azurerm_resource_group.main[each.key].name
  location            = azurerm_resource_group.main[each.key].location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.cluster_tags[each.key]
}

resource "azurerm_nat_gateway" "main" {
  for_each = local.effective_clusters

  name                    = "${local.cluster_name_prefix[each.key]}-nat"
  resource_group_name     = azurerm_resource_group.main[each.key].name
  location                = azurerm_resource_group.main[each.key].location
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = local.cluster_tags[each.key]
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  for_each = local.effective_clusters

  nat_gateway_id       = azurerm_nat_gateway.main[each.key].id
  public_ip_address_id = azurerm_public_ip.nat[each.key].id
}

resource "azurerm_subnet_nat_gateway_association" "private" {
  for_each = local.private_subnet_definitions

  subnet_id      = azurerm_subnet.private[each.key].id
  nat_gateway_id = azurerm_nat_gateway.main[each.value.cluster_key].id
}

resource "azurerm_kubernetes_cluster" "main" {
  for_each = local.effective_clusters

  name                = "${local.cluster_name_prefix[each.key]}-aks"
  location            = azurerm_resource_group.main[each.key].location
  resource_group_name = azurerm_resource_group.main[each.key].name
  dns_prefix          = "${local.cluster_dns_label[each.key]}-aks"
  node_resource_group = local.cluster_node_resource_group[each.key]

  default_node_pool {
    name            = "system"
    node_count      = 1
    vm_size              = var.system_node_vm_size
    os_disk_size_gb = var.node_disk_size
    vnet_subnet_id  = azurerm_subnet.public["${each.key}-public-0"].id
    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    service_cidr   = local.cluster_service_cidr[each.key]
    dns_service_ip = local.cluster_dns_service_ip[each.key]
  }

  tags = local.cluster_tags[each.key]
}

resource "azurerm_kubernetes_cluster_node_pool" "validators" {
  for_each = {
    for cluster_key, cfg in local.effective_clusters :
    cluster_key => cfg
    if cfg.validator_node_count > 0
  }

  name                  = "validators"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main[each.key].id
  vm_size               = var.node_vm_size
  node_count            = each.value.validator_node_count
  os_disk_size_gb       = var.node_disk_size
  vnet_subnet_id        = azurerm_subnet.private["${each.key}-private-0"].id
  enable_auto_scaling   = false
  tags                  = local.cluster_tags[each.key]
}

resource "azurerm_kubernetes_cluster_node_pool" "workers" {
  for_each = {
    for cluster_key, cfg in local.effective_clusters :
    cluster_key => cfg
    if cfg.worker_node_count > 0
  }

  name                  = "workers"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main[each.key].id
  vm_size               = var.node_vm_size
  node_count            = each.value.worker_node_count
  os_disk_size_gb       = var.node_disk_size
  vnet_subnet_id        = azurerm_subnet.private["${each.key}-private-${local.worker_subnet_index[each.key]}"].id
  enable_auto_scaling   = false
  tags                  = local.cluster_tags[each.key]
}

resource "azurerm_managed_disk" "validator_disks" {
  for_each = local.validator_disk_definitions

  name                = "${local.cluster_name_prefix[each.value.cluster_key]}-validator-disk-${each.value.index}"
  location            = azurerm_resource_group.main[each.value.cluster_key].location
  resource_group_name = azurerm_resource_group.main[each.value.cluster_key].name
  storage_account_type = var.storage_type
  create_option       = "Empty"
  disk_size_gb        = var.node_disk_size
  tags                = local.cluster_tags[each.value.cluster_key]
}

resource "azurerm_managed_disk" "worker_disks" {
  for_each = local.worker_disk_definitions

  name                = "${local.cluster_name_prefix[each.value.cluster_key]}-worker-disk-${each.value.index}"
  location            = azurerm_resource_group.main[each.value.cluster_key].location
  resource_group_name = azurerm_resource_group.main[each.value.cluster_key].name
  storage_account_type = var.storage_type
  create_option       = "Empty"
  disk_size_gb        = var.node_disk_size
  tags                = local.cluster_tags[each.value.cluster_key]
}