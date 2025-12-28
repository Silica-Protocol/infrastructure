# Bootstrap configuration to create Terraform state storage
# Run this FIRST with local state, then use remote state for main infrastructure

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  # Using local state for bootstrap (this creates the remote state storage)
  # After running this, the main config can use the created storage account
}

provider "azurerm" {
  features {}
}

# Resource group for Terraform state
resource "azurerm_resource_group" "tfstate" {
  name     = "terraform-state-rg"
  location = var.location

  tags = {
    Purpose = "Terraform State Storage"
    Project = "silica"
  }
}

# Storage account for Terraform state
resource "azurerm_storage_account" "tfstate" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true # Keep history of state files
  }

  tags = {
    Purpose = "Terraform State Storage"
    Project = "silica"
  }
}

# Container for state files
resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}
