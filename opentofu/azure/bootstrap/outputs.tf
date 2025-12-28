output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.tfstate.name
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.tfstate.name
}

output "storage_account_primary_key" {
  description = "Primary access key for storage account"
  value       = azurerm_storage_account.tfstate.primary_access_key
  sensitive   = true
}

output "container_name" {
  description = "Name of the blob container"
  value       = azurerm_storage_container.tfstate.name
}

output "next_steps" {
  description = "Instructions for using remote state"
  value = <<-EOT
    ============================================================================
    BOOTSTRAP COMPLETE - Terraform State Storage Created
    ============================================================================
    
    Set environment variable for state access:
    
    export ARM_ACCESS_KEY=$(tofu output -raw storage_account_primary_key)
    
    Or add to your shell profile:
    
    echo 'export ARM_ACCESS_KEY="$(tofu output -raw storage_account_primary_key)"' >> ~/.zshrc
    
    Now you can initialize the main infrastructure:
    
    cd ../
    tofu init
    
    ============================================================================
  EOT
}
