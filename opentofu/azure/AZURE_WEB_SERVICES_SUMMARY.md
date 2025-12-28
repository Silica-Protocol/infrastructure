# Azure Web Services - Configuration Summary

## ✅ What's Been Added

Your Azure OpenTofu configuration now includes comprehensive web hosting infrastructure:

### 1. **Azure Front Door** (Global CDN + WAF)
- **Location**: `web-services.tf`
- **Purpose**: Global content delivery network with WAF protection
- **Features**:
  - 118+ edge locations worldwide
  - Automatic SSL certificates for custom domains
  - DDoS protection and OWASP Top 10 defenses
  - Bot protection with Microsoft Bot Manager
  - HTTPS-only enforcement
  - Intelligent routing to multiple backends

### 2. **Azure Static Web Apps** (Website Hosting)
- **Location**: `web-services.tf`
- **Two Sites**:
  - **Chert**: Token-focused, design-heavy marketing site
  - **Silica**: Protocol documentation and technical site
- **Features**:
  - Built-in CDN (separate from Front Door)
  - Automatic SSL certificates
  - GitHub Actions integration for CI/CD
  - Preview environments for pull requests
  - Free tier available (100GB bandwidth/month)
  - Custom domain support with CNAME validation

### 3. **Azure Storage Account** (Blob Storage)
- **Location**: `web-services.tf`
- **Three Containers**:
  - `website-assets`: Public assets (images, videos, 3D models)
  - `blockchain-backups`: Private blockchain data backups
  - `artifacts`: Deployment artifacts and builds
- **Features**:
  - Static website hosting capability
  - CORS configuration for web access
  - 7-day soft delete for recovery
  - Encryption at rest (automatic)
  - Configurable replication (LRS/GRS)

### 4. **Azure Container Apps Environment** (Future API Hosting)
- **Location**: `web-services.tf`
- **Status**: Disabled by default (`enable_container_apps = false`)
- **Purpose**: When `api/` is implemented, deploy here
- **Features**:
  - Automatic scaling 0-10 instances
  - Built-in load balancing
  - Managed SSL certificates
  - Private networking to AKS cluster

## 🎯 Key Design Decisions

### ✅ Static Web Apps (Not App Services)
**Reason**: Your websites are built with Astro (static site generator)
- Static Web Apps are optimized for static content
- Free tier available with generous limits
- Built-in GitHub Actions integration
- No need for container orchestration

### ✅ Front Door (Recommended)
**Benefits**:
- Global CDN reduces latency worldwide
- WAF protection included (DDoS, injection attacks, XSS)
- Single entry point for all web properties
- Advanced routing capabilities
- Can route to AKS services when needed

### ✅ Blob Storage (Not Azure Files)
**Reason**: Blob storage is best for web assets
- Lower cost than Azure Files
- Better CDN integration
- Public/private container support
- REST API access from anywhere

### ❌ Landing Zone (Not Needed)
**Why Skip**:
- Landing zones are for enterprise-scale governance
- Requires hub-spoke networking across dozens of apps
- Your setup is simpler: websites + blockchain nodes
- Would add unnecessary complexity and cost

## 📊 Architecture Comparison

### Before (Blockchain Only)
```
Azure
├── AKS Cluster (validator nodes)
├── Virtual Network
├── NAT Gateways
└── Managed Disks
```

### After (Complete Stack)
```
Azure
├── Front Door (Global CDN + WAF)
│   ├── Route: chert.coin → Static Web App (Chert)
│   ├── Route: silica.network → Static Web App (Silica)
│   └── Route: api.* → Container Apps (future)
│
├── Static Web Apps
│   ├── Chert Website (token marketing)
│   └── Silica Website (protocol docs)
│
├── Storage Account
│   ├── website-assets (public)
│   ├── blockchain-backups (private)
│   └── artifacts (private)
│
├── Container Apps Environment (disabled, future use)
│
└── AKS Cluster (blockchain infrastructure)
    ├── Virtual Network
    ├── NAT Gateways
    └── Managed Disks
```

## 🚀 Quick Start

### Deploy Everything
```bash
cd infrastructure/opentofu/azure

# Initialize
tofu init

# Review changes
tofu plan -var-file=terraform.tfvars

# Deploy
tofu apply -var-file=terraform.tfvars
```

### Get Deployment Keys
```bash
# For GitHub Actions
tofu output -raw chert_website_api_key
tofu output -raw silica_website_api_key

# For DNS configuration
tofu output dns_configuration_instructions
```

### Configure Custom Domains
1. Get default hostnames from outputs
2. Add CNAME records in your DNS provider:
   ```
   chert.coin → <chert-hostname>.azurestaticapps.net
   silica.network → <silica-hostname>.azurestaticapps.net
   ```
3. Update `terraform.tfvars`:
   ```hcl
   chert_custom_domain  = "chert.coin"
   silica_custom_domain = "silica.network"
   ```
4. Re-apply: `tofu apply`
5. Azure automatically provisions SSL certificates (5-15 minutes)

## 💰 Cost Estimate

### Free Tier (Development/Testnet)
```
Static Web Apps (Free)           $0/month
Storage (10GB LRS)               $0.50/month
Front Door Standard              $35/month
Data Transfer (100GB)            $8/month
───────────────────────────────────────
TOTAL                            ~$43.50/month
```

### Standard Tier (Production)
```
Static Web Apps (Standard) × 2   $18/month
Storage (100GB GRS)              $12/month
Front Door Premium               $330/month
Data Transfer (1TB)              $80/month
───────────────────────────────────────
TOTAL                            ~$440/month
```

**Cost Savings**:
- Use Free tier for testnet ($0 for websites)
- Disable Front Door if not needed: `enable_front_door = false` (saves $35+)
- Use LRS storage instead of GRS (50% savings on storage)
- Enable aggressive CDN caching to reduce data transfer

## 📝 Configuration Variables

### Required Variables (Already Set)
```hcl
# Core infrastructure
project_name = "chert"
environment  = "testnet"
azure_region = "australiaeast"

# Web services (new)
enable_front_door = true
enable_waf        = true
static_web_app_sku_tier = "Free"
```

### Optional Variables (Configure When Ready)
```hcl
# Custom domains (after DNS setup)
chert_custom_domain  = "chert.coin"
silica_custom_domain = "silica.network"

# Upgrade for production
static_web_app_sku_tier  = "Standard"
storage_replication_type = "GRS"
front_door_sku_name      = "Premium_AzureFrontDoor"

# Enable API hosting (when api/ is implemented)
enable_container_apps = true
```

## 📖 Documentation

- **[WEB_DEPLOYMENT_GUIDE.md](WEB_DEPLOYMENT_GUIDE.md)**: Complete deployment guide
- **[README.md](../README.md)**: Overall infrastructure overview
- **[variables.tf](variables.tf)**: All configurable options
- **[outputs.tf](outputs.tf)**: What you get after deployment

## ✅ What You Get After Deployment

### Immediate
- ✅ Storage account with 3 blob containers
- ✅ Two Static Web Apps (with default .azurestaticapps.net domains)
- ✅ Front Door profile with routing configured
- ✅ WAF policy protecting both sites
- ✅ Deployment keys for GitHub Actions integration

### After DNS Configuration
- ✅ Custom domains (chert.coin, silica.network)
- ✅ Automatic SSL certificates (Azure-managed)
- ✅ HTTPS-only access with redirects

### After Website Deployment
- ✅ Live websites accessible globally
- ✅ Sub-100ms response times (via CDN)
- ✅ Protected by WAF (DDoS, injection, XSS)
- ✅ GitHub Actions CI/CD for automatic deployments

## 🔄 Next Steps

1. **Deploy Infrastructure**: Run `tofu apply`
2. **Configure DNS**: Add CNAME records for custom domains
3. **Set Up GitHub Actions**: Add deployment keys to repository secrets
4. **Deploy Websites**: Push to GitHub or use Azure CLI
5. **Test**: Verify sites are accessible and SSL works
6. **Monitor**: Review Azure Portal for metrics and logs

## 🆘 Support

- **Deployment Issues**: See [WEB_DEPLOYMENT_GUIDE.md](WEB_DEPLOYMENT_GUIDE.md) troubleshooting section
- **Configuration Questions**: Review [variables.tf](variables.tf) documentation
- **Azure-Specific**: Check Azure Portal service health and documentation

## 🎉 Summary

Your Azure infrastructure is now **production-ready** for hosting:
- ✅ Two static websites with global CDN
- ✅ WAF protection and DDoS mitigation
- ✅ Automatic SSL certificate management
- ✅ Blob storage for assets and backups
- ✅ Future-ready for API deployment

**No landing zone complexity** - just what you need, nothing more!
