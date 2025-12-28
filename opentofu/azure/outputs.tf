# Resource group outputs
output "resource_group_names" {
  description = "Map of cluster key to resource group name"
  value       = { for key in keys(local.effective_clusters) : key => azurerm_resource_group.main[key].name }
}

output "resource_group_locations" {
  description = "Map of cluster key to resource group location"
  value       = { for key in keys(local.effective_clusters) : key => azurerm_resource_group.main[key].location }
}

# Virtual network outputs
output "virtual_network_ids" {
  description = "Map of cluster key to Virtual Network ID"
  value       = { for key in keys(local.effective_clusters) : key => azurerm_virtual_network.main[key].id }
}

output "virtual_network_address_spaces" {
  description = "Map of cluster key to VNet address space"
  value       = { for key in keys(local.effective_clusters) : key => azurerm_virtual_network.main[key].address_space }
}

# Subnet outputs
output "public_subnet_ids" {
  description = "Map of cluster key to list of public subnet IDs"
  value = {
    for cluster_key in keys(local.effective_clusters) :
    cluster_key => [
      for subnet_index in range(local.cluster_subnet_count[cluster_key]) :
      azurerm_subnet.public["${cluster_key}-public-${subnet_index}"].id
    ]
  }
}

output "private_subnet_ids" {
  description = "Map of cluster key to list of private subnet IDs"
  value = {
    for cluster_key in keys(local.effective_clusters) :
    cluster_key => [
      for subnet_index in range(local.cluster_subnet_count[cluster_key]) :
      azurerm_subnet.private["${cluster_key}-private-${subnet_index}"].id
    ]
  }
}

# AKS cluster outputs
output "aks_cluster_names" {
  description = "Map of cluster key to AKS cluster name"
  value       = { for key in keys(local.effective_clusters) : key => azurerm_kubernetes_cluster.main[key].name }
}

output "aks_cluster_ids" {
  description = "Map of cluster key to AKS cluster ID"
  value       = { for key in keys(local.effective_clusters) : key => azurerm_kubernetes_cluster.main[key].id }
}

output "aks_kube_config_raw" {
  description = "Map of cluster key to raw kubeconfig"
  value       = { for key in keys(local.effective_clusters) : key => azurerm_kubernetes_cluster.main[key].kube_config_raw }
  sensitive   = true
}

output "aks_kube_config_commands" {
  description = "Convenience commands to fetch kubeconfig per cluster"
  value       = { for key in keys(local.effective_clusters) : key => "az aks get-credentials --resource-group ${azurerm_resource_group.main[key].name} --name ${azurerm_kubernetes_cluster.main[key].name}" }
}

output "aks_cluster_fqdns" {
  description = "Map of cluster key to AKS API server FQDN"
  value       = { for key in keys(local.effective_clusters) : key => azurerm_kubernetes_cluster.main[key].fqdn }
}

# Node pool outputs
output "validator_node_pool_ids" {
  description = "Validator node pool IDs (only clusters with validators)"
  value       = { for key, pool in azurerm_kubernetes_cluster_node_pool.validators : key => pool.id }
}

output "worker_node_pool_ids" {
  description = "Worker node pool IDs (only clusters with workers)"
  value       = { for key, pool in azurerm_kubernetes_cluster_node_pool.workers : key => pool.id }
}

# Storage outputs
output "validator_disk_ids" {
  description = "Map of validator disk IDs grouped by cluster"
  value = {
    for cluster_key in keys(local.effective_clusters) :
    cluster_key => [
      for disk in values(local.validator_disk_definitions) :
      azurerm_managed_disk.validator_disks[disk.key].id
      if disk.cluster_key == cluster_key
    ]
  }
}

output "worker_disk_ids" {
  description = "Map of worker disk IDs grouped by cluster"
  value = {
    for cluster_key in keys(local.effective_clusters) :
    cluster_key => [
      for disk in values(local.worker_disk_definitions) :
      azurerm_managed_disk.worker_disks[disk.key].id
      if disk.cluster_key == cluster_key
    ]
  }
}

# Network outputs
output "nat_gateway_public_ips" {
  description = "Map of cluster key to NAT gateway public IP"
  value       = { for key in keys(local.effective_clusters) : key => azurerm_public_ip.nat[key].ip_address }
}

output "nat_gateway_ids" {
  description = "Map of cluster key to NAT gateway ID"
  value       = { for key in keys(local.effective_clusters) : key => azurerm_nat_gateway.main[key].id }
}

# Security outputs
output "aks_cluster_client_certificate" {
  description = "Client certificates for AKS clusters"
  value       = { for key in keys(local.effective_clusters) : key => azurerm_kubernetes_cluster.main[key].kube_config[0].client_certificate }
  sensitive   = true
}

output "aks_cluster_client_key" {
  description = "Client keys for AKS clusters"
  value       = { for key in keys(local.effective_clusters) : key => azurerm_kubernetes_cluster.main[key].kube_config[0].client_key }
  sensitive   = true
}

output "aks_cluster_cluster_ca_certificate" {
  description = "CA certificates for AKS clusters"
  value       = { for key in keys(local.effective_clusters) : key => azurerm_kubernetes_cluster.main[key].kube_config[0].cluster_ca_certificate }
  sensitive   = true
}

# ============================================================================
# Web Services Outputs
# ============================================================================

# Storage Account outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key for storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "website_assets_container_url" {
  description = "URL of the website assets container"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.website_assets.name}"
}

# Static Web Apps outputs
output "chert_website_url" {
  description = "Default URL for Chert website"
  value       = "https://${azurerm_static_web_app.chert_website.default_host_name}"
}

output "chert_website_api_key" {
  description = "API key for Chert Static Web App deployment"
  value       = azurerm_static_web_app.chert_website.api_key
  sensitive   = true
}

output "silica_website_url" {
  description = "Default URL for Silica website"
  value       = "https://${azurerm_static_web_app.silica_website.default_host_name}"
}

output "silica_website_api_key" {
  description = "API key for Silica Static Web App deployment"
  value       = azurerm_static_web_app.silica_website.api_key
  sensitive   = true
}

output "chert_custom_domain_validation" {
  description = "DNS validation token for Chert custom domain"
  value       = var.chert_custom_domain != "" ? azurerm_static_web_app_custom_domain.chert_domain[0].validation_token : null
}

output "silica_custom_domain_validation" {
  description = "DNS validation token for Silica custom domain"
  value       = var.silica_custom_domain != "" ? azurerm_static_web_app_custom_domain.silica_domain[0].validation_token : null
}

# Container Apps outputs (conditional)
output "container_app_environment_id" {
  description = "ID of Container Apps environment"
  value       = var.enable_container_apps ? azurerm_container_app_environment.main[0].id : null
}

output "container_app_environment_default_domain" {
  description = "Default domain of Container Apps environment"
  value       = var.enable_container_apps ? azurerm_container_app_environment.main[0].default_domain : null
}

# Front Door outputs (conditional)
output "front_door_profile_id" {
  description = "ID of the Front Door profile"
  value       = var.enable_front_door ? azurerm_cdn_frontdoor_profile.main[0].id : null
}

output "front_door_chert_endpoint_url" {
  description = "Front Door endpoint URL for Chert website"
  value       = var.enable_front_door ? "https://${azurerm_cdn_frontdoor_endpoint.chert[0].host_name}" : null
}

output "front_door_silica_endpoint_url" {
  description = "Front Door endpoint URL for Silica website"
  value       = var.enable_front_door ? "https://${azurerm_cdn_frontdoor_endpoint.silica[0].host_name}" : null
}

output "front_door_waf_policy_id" {
  description = "ID of the Front Door WAF policy"
  value       = var.enable_front_door && var.enable_waf ? azurerm_cdn_frontdoor_firewall_policy.main[0].id : null
}

# DNS Configuration Instructions
output "dns_configuration_instructions" {
  description = "Instructions for configuring DNS records"
  value = <<-EOT
    ============================================================================
    DNS CONFIGURATION REQUIRED
    ============================================================================
    
    1. CHERT WEBSITE (${var.chert_custom_domain != "" ? var.chert_custom_domain : "Not configured"})
       - Add CNAME record: ${var.chert_custom_domain} -> ${azurerm_static_web_app.chert_website.default_host_name}
       ${var.enable_front_door ? "- Or CNAME to Front Door: ${azurerm_cdn_frontdoor_endpoint.chert[0].host_name}" : ""}
    
    2. SILICA WEBSITE (${var.silica_custom_domain != "" ? var.silica_custom_domain : "Not configured"})
       - Add CNAME record: ${var.silica_custom_domain} -> ${azurerm_static_web_app.silica_website.default_host_name}
       ${var.enable_front_door ? "- Or CNAME to Front Door: ${azurerm_cdn_frontdoor_endpoint.silica[0].host_name}" : ""}
    
    3. SSL CERTIFICATES
       - Azure Static Web Apps: Automatic (no action needed)
       - Front Door: Automatic managed certificates
    
    4. DEPLOYMENT KEYS (retrieve from outputs)
       - Chert: Use 'tofu output -raw chert_website_api_key'
       - Silica: Use 'tofu output -raw silica_website_api_key'
    
    ============================================================================
  EOT
}