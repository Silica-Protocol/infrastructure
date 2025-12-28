# Azure Web Services Deployment Guide

## Overview

This guide covers deploying the Chert and Silica websites along with supporting infrastructure to Azure using OpenTofu.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Azure Front Door (Global)                  │
│  • Global CDN with edge caching                             │
│  • WAF protection (DDoS, OWASP Top 10)                     │
│  • Automatic SSL certificates                               │
│  • HTTPS-only enforcement                                   │
└────────────┬────────────────────────────────┬───────────────┘
             │                                │
             │                                │
   ┌─────────▼──────────┐         ┌─────────▼──────────┐
   │  Static Web App    │         │  Static Web App    │
   │  chert.coin        │         │  silica.network    │
   │  (Token-focused)   │         │  (Protocol docs)   │
   └────────────────────┘         └────────────────────┘
             │                                │
             └────────────┬───────────────────┘
                          │
                ┌─────────▼──────────┐
                │  Storage Account   │
                │  • Website assets  │
                │  • 3D models       │
                │  • Backups         │
                └────────────────────┘
```

## What's Included

### ✅ Azure Front Door
- **Global CDN**: Edge caching across 118+ locations worldwide
- **WAF**: Protection against DDoS, SQL injection, XSS, bots
- **SSL**: Automatic managed certificates for custom domains
- **Routing**: Intelligent traffic routing to Static Web Apps
- **Performance**: Sub-100ms response times globally

### ✅ Azure Static Web Apps
- **Chert Website**: Token-focused, design-heavy site (website/chert/)
- **Silica Website**: Protocol documentation site (website/silica/)
- **Features**:
  - Automatic SSL certificates
  - Global CDN built-in
  - GitHub Actions integration
  - Preview environments for PRs
  - Custom domain support

### ✅ Azure Storage Account
- **Blob Containers**:
  - `website-assets`: Public assets (images, videos, 3D models)
  - `blockchain-backups`: Private blockchain data backups
  - `artifacts`: Deployment artifacts and builds
- **Features**:
  - 99.9% availability SLA
  - Automatic encryption at rest
  - CORS configuration for web access
  - 7-day soft delete for recovery

### 🔜 Azure Container Apps (Future)
- **API Service**: For when api/ is implemented
- **Features**:
  - Automatic scaling 0-10 instances
  - Built-in load balancing
  - Private networking to AKS
  - Managed SSL certificates

## Prerequisites

1. **Azure Account**: With appropriate permissions
2. **OpenTofu**: Version 1.5+ installed
3. **Azure CLI**: For authentication and management
4. **GitHub Account**: For Static Web Apps deployment
5. **DNS Provider**: Access to manage DNS records

## Deployment Steps

### Step 1: Azure Authentication

```bash
# Login to Azure
az login

# Set subscription (if you have multiple)
az account set --subscription "Your Subscription Name"

# Verify current subscription
az account show
```

### Step 2: Initialize OpenTofu

```bash
cd infrastructure/opentofu/azure

# Initialize providers and modules
tofu init

# Validate configuration
tofu validate
```

### Step 3: Configure Variables (Optional)

Edit `terraform.tfvars` to customize:

```hcl
# Enable/disable Front Door
enable_front_door = true  # Recommended for production

# Upgrade Static Web Apps tier for production
static_web_app_sku_tier = "Standard"  # Unlocks custom auth, staging slots

# Add custom domains (after DNS is configured)
chert_custom_domain  = "chert.coin"
silica_custom_domain = "silica.network"

# Upgrade storage replication for production
storage_replication_type = "GRS"  # Geo-redundant storage
```

### Step 4: Plan Deployment

```bash
# Preview changes (recommended)
tofu plan -var-file=terraform.tfvars

# Save plan for review
tofu plan -var-file=terraform.tfvars -out=deployment.tfplan
```

### Step 5: Deploy Infrastructure

```bash
# Apply infrastructure changes
tofu apply -var-file=terraform.tfvars

# Or use saved plan
tofu apply deployment.tfplan
```

This will create:
- ✅ Storage Account with blob containers
- ✅ Static Web Apps for Chert and Silica
- ✅ Front Door profile with routing
- ✅ WAF policy with security rules

### Step 6: Retrieve Deployment Keys

```bash
# Get Chert website deployment key
tofu output -raw chert_website_api_key

# Get Silica website deployment key
tofu output -raw silica_website_api_key

# Get storage account connection string
tofu output -raw storage_account_primary_connection_string
```

**⚠️ IMPORTANT**: Save these keys securely - you'll need them for GitHub Actions.

## Website Deployment

### Option A: GitHub Actions (Recommended)

Azure Static Web Apps automatically creates GitHub Actions workflows.

1. **Configure GitHub Secrets**:
   ```bash
   # Add to repository secrets:
   AZURE_STATIC_WEB_APPS_API_TOKEN_CHERT=<chert_website_api_key>
   AZURE_STATIC_WEB_APPS_API_TOKEN_SILICA=<silica_website_api_key>
   ```

2. **Push to Repository**:
   - Chert website: Push to `main` branch in `website/chert/`
   - Silica website: Push to `main` branch in `website/silica/`
   - GitHub Actions will automatically build and deploy

3. **Verify Deployment**:
   ```bash
   # Get deployed URLs
   tofu output chert_website_url
   tofu output silica_website_url
   ```

### Option B: Azure CLI (Manual)

```bash
cd website/chert

# Build Astro site
npm install
npm run build

# Deploy to Azure (using SWA CLI)
npx @azure/static-web-apps-cli deploy \
  --app-location dist \
  --deployment-token $(tofu output -raw chert_website_api_key)
```

Repeat for Silica website in `website/silica/`.

## DNS Configuration

### Step 1: Get DNS Information

```bash
# View DNS configuration instructions
tofu output dns_configuration_instructions

# Get specific endpoints
tofu output chert_website_url
tofu output silica_website_url
tofu output front_door_chert_endpoint_url
tofu output front_door_silica_endpoint_url
```

### Step 2: Add DNS Records

**For Direct Static Web Apps** (without Front Door):
```
# Chert
CNAME  chert.coin  →  <chert-default-hostname>.azurestaticapps.net

# Silica
CNAME  silica.network  →  <silica-default-hostname>.azurestaticapps.net
```

**For Front Door** (recommended - global CDN):
```
# Chert
CNAME  chert.coin  →  <front-door-chert-endpoint>.azurefd.net

# Silica
CNAME  silica.network  →  <front-door-silica-endpoint>.azurefd.net
```

### Step 3: Verify SSL Certificates

```bash
# Check certificate status (usually takes 5-15 minutes)
az staticwebapp hostname list \
  --name <static-web-app-name> \
  --resource-group <resource-group-name>
```

Azure automatically provisions SSL certificates - **no action required on your part**.

## Uploading Assets to Blob Storage

### Step 1: Get Storage Credentials

```bash
# Get storage account name
STORAGE_ACCOUNT=$(tofu output -raw storage_account_name)

# Get access key
STORAGE_KEY=$(tofu output -raw storage_account_primary_access_key)
```

### Step 2: Upload Files

```bash
# Upload website assets (images, videos, 3D models)
az storage blob upload-batch \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY \
  --destination website-assets \
  --source ./assets/ \
  --overwrite

# Set public read access for assets
az storage blob list \
  --account-name $STORAGE_ACCOUNT \
  --container-name website-assets \
  --query "[].name" -o tsv | \
  xargs -I {} az storage blob update \
    --account-name $STORAGE_ACCOUNT \
    --container-name website-assets \
    --name {} \
    --content-cache-control "public, max-age=31536000"
```

### Step 3: Reference Assets in Code

Assets are accessible at:
```
https://<storage-account>.blob.core.windows.net/website-assets/<filename>
```

Example in Astro:
```astro
---
const assetUrl = import.meta.env.PUBLIC_AZURE_BLOB_URL;
---

<img src={`${assetUrl}/chert-logo.webp`} alt="Chert Logo" />
<video src={`${assetUrl}/performance-demo.mp4`} />
```

## Monitoring and Maintenance

### View Deployment Logs

```bash
# Static Web App deployment history
az staticwebapp show \
  --name <static-web-app-name> \
  --resource-group <resource-group-name>

# Front Door metrics
az monitor metrics list \
  --resource <front-door-id> \
  --metric TotalRequests \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z
```

### Check WAF Activity

```bash
# View WAF policy status
az network front-door waf-policy show \
  --name <waf-policy-name> \
  --resource-group <resource-group-name>

# View blocked requests
az monitor activity-log list \
  --resource-id <waf-policy-id> \
  --start-time 2024-01-01T00:00:00Z
```

### Update Infrastructure

```bash
# Make changes to .tf files
vim terraform.tfvars

# Preview changes
tofu plan -var-file=terraform.tfvars

# Apply updates
tofu apply -var-file=terraform.tfvars
```

## Cost Optimization

### Free Tier Usage

Current configuration uses Free tier where possible:
- ✅ **Static Web Apps**: Free tier (100GB bandwidth/month)
- ✅ **Storage Account**: Pay-as-you-go (first 5GB free)
- ✅ **Front Door**: Standard tier (~$35/month + data transfer)
- ✅ **WAF**: Included with Front Door Standard

### Estimated Monthly Costs

**Development/Testnet** (current config):
- Static Web Apps (Free): $0
- Storage (LRS, ~10GB): ~$0.50
- Front Door Standard: ~$35
- Data Transfer (100GB): ~$8
- **Total**: ~$43.50/month

**Production** (upgraded config):
- Static Web Apps (Standard): $9/app × 2 = $18
- Storage (GRS, ~100GB): ~$12
- Front Door Premium: ~$330 (adds Private Link, better WAF)
- Data Transfer (1TB): ~$80
- **Total**: ~$440/month

### Cost Saving Tips

1. **Use Free tier** for development/testnet
2. **Disable Front Door** if not needed: `enable_front_door = false`
3. **Use LRS storage** instead of GRS for non-critical data
4. **Enable CDN caching** to reduce origin requests
5. **Compress assets** (WebP images, gzipped JS/CSS)

## Troubleshooting

### Issue: Custom Domain Not Working

**Solution**:
1. Verify DNS propagation: `nslookup chert.coin`
2. Check CNAME record is correct
3. Wait 24-48 hours for DNS propagation
4. Verify SSL certificate status in Azure Portal

### Issue: Static Web App Build Fails

**Solution**:
1. Check GitHub Actions logs for errors
2. Verify `astro.config.mjs` has correct output config
3. Ensure `package.json` has correct build script
4. Test build locally: `npm run build`

### Issue: Assets Not Loading

**Solution**:
1. Verify blob container is public: `container_access_type = "blob"`
2. Check CORS settings in storage account
3. Verify asset URLs are correct in code
4. Test direct blob URL in browser

### Issue: WAF Blocking Legitimate Traffic

**Solution**:
1. Set WAF to Detection mode: `waf_mode = "Detection"`
2. Review blocked requests in Azure Monitor
3. Create custom WAF rules to allow traffic
4. Test with WAF disabled temporarily

## Next Steps

### Phase 1: Basic Deployment (Current)
- ✅ Deploy Static Web Apps
- ✅ Configure Front Door
- ✅ Set up blob storage
- ⏳ Configure custom domains
- ⏳ Deploy websites via GitHub Actions

### Phase 2: API Integration (Future)
- ⏳ Implement api/ service (see api/README.md)
- ⏳ Enable Container Apps: `enable_container_apps = true`
- ⏳ Deploy API to Container Apps
- ⏳ Add API routes to Front Door

### Phase 3: Production Hardening
- ⏳ Upgrade to Standard/Premium tiers
- ⏳ Enable geo-redundant storage (GRS)
- ⏳ Configure advanced WAF rules
- ⏳ Set up Azure Monitor alerts
- ⏳ Implement backup automation

## Multi-Region Validator Deployment

The infrastructure module now supports spinning up **multiple AKS clusters in one apply** using the `regional_clusters` map inside your `.tfvars` file. Each entry provisions a full stack (resource group, VNet, NAT, AKS, disks) in its own Azure region.

```hcl
regional_clusters = {
  australia_east = {
    azure_region         = "australiaeast"
    vnet_cidr            = "10.0.0.0/16"
    availability_zones   = ["1"]
    validator_node_count = 1
    worker_node_count    = 0
  }

  australia_southeast = {
    azure_region         = "australiasoutheast"
    vnet_cidr            = "10.1.0.0/16"
    availability_zones   = ["1"]
    validator_node_count = 1
    worker_node_count    = 0
  }
}
```

**Guidelines**

1. Give every region a **unique CIDR** (e.g., 10.0.0.0/16, 10.1.0.0/16, ...).
2. Set per-region `validator_node_count`/`worker_node_count` to stay within regional vCPU quotas.
3. Leave `regional_clusters` empty to fall back to the legacy single-region variables for quick tests.
4. Outputs such as `aks_cluster_names`, `nat_gateway_public_ips`, etc., now return **maps keyed by cluster** (use `tofu output <name>` to inspect).
5. To add/remove a region, edit the map entry and re-run `tofu apply`—OpenTofu will create/destroy only the affected cluster.

This approach lets you keep one node per Australian region (or any geography) without juggling separate state files or workspaces.

## Additional Resources

- [Azure Static Web Apps Documentation](https://docs.microsoft.com/en-us/azure/static-web-apps/)
- [Azure Front Door Documentation](https://docs.microsoft.com/en-us/azure/frontdoor/)
- [Azure Blob Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/blobs/)
- [Astro Deployment Guide](https://docs.astro.build/en/guides/deploy/microsoft-azure/)
- [OpenTofu Documentation](https://opentofu.org/docs/)

## Support

For issues or questions:
1. Review this guide and troubleshooting section
2. Check Azure Portal for service health
3. Review GitHub Actions logs for deployment errors
4. Consult Azure documentation for specific services
5. Contact team in project chat/Slack
