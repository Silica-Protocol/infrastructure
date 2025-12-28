# Azure Web Services Configuration
# Provides hosting for Chert & Silica websites, API, and Front Door CDN

# ============================================================================
# Web Resource Group (global web assets live here)
# =========================================================================

resource "azurerm_resource_group" "web" {
  name     = "${local.name_prefix}-web-rg"
  location = local.effective_clusters[local.primary_cluster_key].azure_region
  tags     = local.common_tags
}

# =========================================================================
# Storage Account - For blobs, static assets, and backups
# ============================================================================

resource "azurerm_storage_account" "main" {
  name                     = "silica${var.environment}${random_id.suffix.hex}"
  resource_group_name      = azurerm_resource_group.web.name
  location                 = azurerm_resource_group.web.location
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"

  # Enable static website hosting for fallback/assets
  static_website {
    index_document = "index.html"
  }

  # Security settings
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = true
  https_traffic_only_enabled      = true

  # Blob properties
  blob_properties {
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "HEAD", "OPTIONS"]
      allowed_origins    = ["*"]
      exposed_headers    = ["*"]
      max_age_in_seconds = 3600
    }

    delete_retention_policy {
      days = 7
    }
  }

  tags = local.common_tags
}

# Container for website assets (images, videos, 3D models)
resource "azurerm_storage_container" "website_assets" {
  name                  = "website-assets"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "blob" # Public read access
}

# Container for blockchain backups
resource "azurerm_storage_container" "blockchain_backups" {
  name                  = "blockchain-backups"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Container for deployment artifacts
resource "azurerm_storage_container" "artifacts" {
  name                  = "artifacts"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# ============================================================================
# Static Web Apps - For Chert & Silica websites
# ============================================================================

# Chert website (chert.coin) - Token-focused, design-heavy
resource "azurerm_static_web_app" "chert_website" {
  name                = "${local.name_prefix}-chert-web"
  resource_group_name = azurerm_resource_group.web.name
  location            = var.static_web_app_location # Static Web Apps have limited regions
  sku_tier            = var.static_web_app_sku_tier
  sku_size            = var.static_web_app_sku_size

  tags = merge(
    local.common_tags,
    {
      Website = "chert-coin"
      Purpose = "token-marketing"
    }
  )
}

# Silica website (silica.network) - Protocol-focused, technical
resource "azurerm_static_web_app" "silica_website" {
  name                = "${local.name_prefix}-silica-web"
  resource_group_name = azurerm_resource_group.web.name
  location            = var.static_web_app_location
  sku_tier            = var.static_web_app_sku_tier
  sku_size            = var.static_web_app_sku_size

  tags = merge(
    local.common_tags,
    {
      Website = "silica-network"
      Purpose = "protocol-documentation"
    }
  )
}

# Custom domain configuration for Chert website
resource "azurerm_static_web_app_custom_domain" "chert_domain" {
  count              = var.chert_custom_domain != "" ? 1 : 0
  static_web_app_id  = azurerm_static_web_app.chert_website.id
  domain_name        = var.chert_custom_domain
  validation_type    = "cname-delegation"
}

# Custom domain configuration for Silica website
resource "azurerm_static_web_app_custom_domain" "silica_domain" {
  count              = var.silica_custom_domain != "" ? 1 : 0
  static_web_app_id  = azurerm_static_web_app.silica_website.id
  domain_name        = var.silica_custom_domain
  validation_type    = "cname-delegation"
}

# ============================================================================
# Container Apps Environment - For future API deployment
# ============================================================================

# Log Analytics Workspace for Container Apps
resource "azurerm_log_analytics_workspace" "container_apps" {
  count               = var.enable_container_apps ? 1 : 0
  name                = "${local.name_prefix}-containerapp-logs"
  resource_group_name = azurerm_resource_group.web.name
  location            = azurerm_resource_group.web.location
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = local.common_tags
}

# Container Apps Environment
resource "azurerm_container_app_environment" "main" {
  count                      = var.enable_container_apps ? 1 : 0
  name                       = "${local.name_prefix}-containerapp-env"
  resource_group_name        = azurerm_resource_group.web.name
  location                   = azurerm_resource_group.web.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.container_apps[0].id

  tags = local.common_tags
}

# Container App for API (placeholder - commented until api/ is implemented)
# Uncomment when ready to deploy the API service
/*
resource "azurerm_container_app" "api" {
  name                         = "${local.name_prefix}-api"
  resource_group_name          = azurerm_resource_group.web.name
  container_app_environment_id = azurerm_container_app_environment.main[0].id
  revision_mode                = "Single"

  template {
    container {
      name   = "chert-api"
      image  = var.api_container_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "DATABASE_URL"
        value = "postgresql://..." # Configure when API is ready
      }
    }

    min_replicas = 1
    max_replicas = 10
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = local.common_tags
}
*/

# ============================================================================
# Azure Front Door - Global CDN, WAF, and unified routing
# ============================================================================

resource "azurerm_cdn_frontdoor_profile" "main" {
  count               = var.enable_front_door ? 1 : 0
  name                = "${local.name_prefix}-fd-profile"
  resource_group_name = azurerm_resource_group.web.name
  sku_name            = var.front_door_sku_name

  tags = local.common_tags
}

# Endpoint for Chert website
resource "azurerm_cdn_frontdoor_endpoint" "chert" {
  count                    = var.enable_front_door ? 1 : 0
  name                     = "${local.name_prefix}-chert-endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main[0].id

  tags = local.common_tags
}

# Endpoint for Silica website
resource "azurerm_cdn_frontdoor_endpoint" "silica" {
  count                    = var.enable_front_door ? 1 : 0
  name                     = "${local.name_prefix}-silica-endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main[0].id

  tags = local.common_tags
}

# Origin group for Chert Static Web App
resource "azurerm_cdn_frontdoor_origin_group" "chert" {
  count                    = var.enable_front_door ? 1 : 0
  name                     = "chert-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main[0].id

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }

  health_probe {
    path                = "/"
    request_type        = "HEAD"
    protocol            = "Https"
    interval_in_seconds = 100
  }
}

# Origin group for Silica Static Web App
resource "azurerm_cdn_frontdoor_origin_group" "silica" {
  count                    = var.enable_front_door ? 1 : 0
  name                     = "silica-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main[0].id

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }

  health_probe {
    path                = "/"
    request_type        = "HEAD"
    protocol            = "Https"
    interval_in_seconds = 100
  }
}

# Origin for Chert Static Web App
resource "azurerm_cdn_frontdoor_origin" "chert" {
  count                         = var.enable_front_door ? 1 : 0
  name                          = "chert-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.chert[0].id

  enabled                        = true
  host_name                      = azurerm_static_web_app.chert_website.default_host_name
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = azurerm_static_web_app.chert_website.default_host_name
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
}

# Origin for Silica Static Web App
resource "azurerm_cdn_frontdoor_origin" "silica" {
  count                         = var.enable_front_door ? 1 : 0
  name                          = "silica-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.silica[0].id

  enabled                        = true
  host_name                      = azurerm_static_web_app.silica_website.default_host_name
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = azurerm_static_web_app.silica_website.default_host_name
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
}

# Route for Chert website
resource "azurerm_cdn_frontdoor_route" "chert" {
  count                         = var.enable_front_door ? 1 : 0
  name                          = "chert-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.chert[0].id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.chert[0].id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.chert[0].id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  link_to_default_domain = true
  https_redirect_enabled = true
}

# Route for Silica website
resource "azurerm_cdn_frontdoor_route" "silica" {
  count                         = var.enable_front_door ? 1 : 0
  name                          = "silica-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.silica[0].id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.silica[0].id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.silica[0].id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  link_to_default_domain = true
  https_redirect_enabled = true
}

# WAF Policy for Front Door
resource "azurerm_cdn_frontdoor_firewall_policy" "main" {
  count                             = var.enable_front_door && var.enable_waf ? 1 : 0
  name                              = "${replace(local.name_prefix, "-", "")}wafpolicy"
  resource_group_name               = azurerm_resource_group.web.name
  sku_name                          = var.front_door_sku_name
  enabled                           = true
  mode                              = var.waf_mode
  redirect_url                      = var.waf_redirect_url
  custom_block_response_status_code = 403
  custom_block_response_body        = base64encode("Access denied by WAF policy")

  managed_rule {
    type    = "DefaultRuleSet"
    version = "1.0"
    action  = "Block"
  }

  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.0"
    action  = "Block"
  }

  tags = local.common_tags
}

# Security policy linking WAF to endpoints
resource "azurerm_cdn_frontdoor_security_policy" "main" {
  count                    = var.enable_front_door && var.enable_waf ? 1 : 0
  name                     = "${local.name_prefix}-security-policy"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main[0].id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.main[0].id

      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.chert[0].id
        }
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.silica[0].id
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}
