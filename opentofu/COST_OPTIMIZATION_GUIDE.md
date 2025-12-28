# Cost Optimization Guide - CDN and WAF Options

## Overview

Since you're using both AWS and Azure, here's a breakdown of CDN/WAF options and costs.

## Cost Comparison

### Option 1: No CDN (Cheapest) - **FREE**
**What You Get**:
- ✅ Azure Static Web Apps built-in CDN (included)
- ✅ Basic DDoS protection (Azure infrastructure level)
- ✅ Automatic SSL certificates
- ✅ Global distribution (limited PoPs)

**Cost**: $0/month

**Limitations**:
- ❌ No advanced WAF rules
- ❌ No custom bot protection
- ❌ Limited CDN edge locations vs dedicated service
- ❌ No unified routing across multiple backends

**Good For**: Development, testnet, low-traffic production

---

### Option 2: AWS CloudFront + WAF (Recommended) - **~$10-20/month**
**What You Get**:
- ✅ Global CDN with 450+ edge locations
- ✅ AWS WAF with custom rules
- ✅ DDoS protection via AWS Shield Standard (free)
- ✅ Can serve Azure Static Web Apps as origin
- ✅ Much cheaper than Azure Front Door

**Cost Breakdown**:
```
CloudFront Data Transfer:
  - First 10 TB: $0.085/GB = $85/TB
  - For 100GB: ~$8.50/month
  - For 1TB: ~$85/month

CloudFront Requests:
  - 10,000 HTTPS requests = $0.01
  - 1M requests: ~$1/month

AWS WAF:
  - Base: $5/month per Web ACL
  - Rules: $1/month per rule (1-10 rules typical)
  - Requests: $0.60 per 1M requests

Total for 100GB traffic:
  - CloudFront: $8.50
  - WAF: $5 + $5 (5 rules) + $1 = $11
  - TOTAL: ~$19.50/month
```

**How to Set Up**:
1. Deploy Azure Static Web Apps (as configured)
2. Create CloudFront distribution with Azure as origin
3. Point DNS to CloudFront (not directly to Azure)
4. Add AWS WAF to CloudFront distribution

**Architecture**:
```
User → CloudFront (AWS) → Azure Static Web Apps
       └─ AWS WAF
```

---

### Option 3: Azure Front Door Standard - **~$35-50/month**
**What You Get**:
- ✅ Global CDN with 118+ edge locations
- ✅ Integrated WAF with managed rules
- ✅ Bot protection included
- ✅ Native Azure integration
- ✅ Advanced routing capabilities

**Cost Breakdown**:
```
Front Door Standard:
  - Base: $35/month
  - Data Transfer (first 10TB): $0.04/GB outbound
  - 100GB: $35 + $4 = $39/month
  - 1TB: $35 + $40 = $75/month

WAF (included with Standard):
  - Managed rules: Included
  - Custom rules: $5/rule/month
```

**Configuration**: Already in your OpenTofu config, just set:
```hcl
enable_front_door = true
```

---

### Option 4: Cloudflare (Alternative) - **$0-20/month**
**What You Get**:
- ✅ Global CDN (275+ locations)
- ✅ Basic WAF rules (Free tier)
- ✅ DDoS protection (Free tier)
- ✅ Advanced WAF ($20/month Pro plan)
- ✅ Works with both AWS and Azure origins

**Cost Breakdown**:
```
Free Tier:
  - Unlimited bandwidth (yes, really)
  - Basic WAF rules
  - DDoS protection
  - SSL certificates
  - Cost: $0/month

Pro Tier ($20/month):
  - Everything in Free
  - Advanced WAF rules
  - Image optimization
  - Mobile optimization
  - Cost: $20/month per domain
```

**How to Set Up**:
1. Deploy Azure Static Web Apps
2. Add domain to Cloudflare
3. Update DNS nameservers to Cloudflare
4. Configure SSL/TLS (Full mode)

---

## Recommendation by Use Case

### For Testnet / Development
**Use**: Azure Static Web Apps built-in CDN (Free)
- Cost: $0/month
- What you get: Basic CDN, SSL, DDoS protection
- Deploy with: `enable_front_door = false` (current config)

### For Small Production (<100GB/month traffic)
**Use**: AWS CloudFront + WAF
- Cost: ~$10-20/month
- Why: Much cheaper than Azure Front Door
- Better global coverage than Static Web Apps built-in

### For Medium Production (100GB-1TB/month)
**Use**: Cloudflare Pro
- Cost: $20/month per domain ($40 for both sites)
- Why: Unlimited bandwidth, good WAF, best value
- Easiest to manage

### For Enterprise / High Security
**Use**: Azure Front Door Standard/Premium
- Cost: $35-330/month
- Why: Best Azure integration, advanced features
- Premium adds Private Link, premium WAF rules

---

## Multi-Cloud Strategy (AWS + Azure)

### Architecture 1: CloudFront in Front (Recommended for Cost)
```
User → AWS CloudFront → Azure Static Web Apps
       └─ AWS WAF

Benefits:
- Leverage AWS free tier (first 1TB data transfer)
- Cheaper WAF ($5-10/month vs $35/month)
- Can add AWS Shield Advanced for DDoS if needed
- Use AWS for primary infrastructure, Azure for websites

Cost: ~$10-20/month vs ~$35-50/month (saves $20-30/month)
```

**OpenTofu Configuration** (create `aws/cloudfront.tf`):
```hcl
resource "aws_cloudfront_distribution" "chert_website" {
  enabled = true
  
  origin {
    domain_name = azurerm_static_site.chert_website.default_host_name
    origin_id   = "azure-static-web-app"
    
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "azure-static-web-app"
    viewer_protocol_policy = "redirect-to-https"
    
    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
    }
  }
  
  # WAF association
  web_acl_id = aws_wafv2_web_acl.main.arn
  
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

resource "aws_wafv2_web_acl" "main" {
  name  = "chert-waf"
  scope = "CLOUDFRONT"
  
  default_action {
    allow {}
  }
  
  # AWS Managed Rules (free)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    
    override_action {
      none {}
    }
    
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }
}
```

### Architecture 2: Azure Front Door (Simpler, More Expensive)
```
User → Azure Front Door → Azure Static Web Apps
       └─ Azure WAF

Benefits:
- All in one cloud (simpler management)
- Native Azure integration
- Single invoice

Cost: ~$35-50/month
```

**Configuration**: Already done, just set:
```hcl
enable_front_door = true
```

---

## Cost Summary Table

| Solution | Monthly Cost | Setup Complexity | Best For |
|----------|-------------|------------------|----------|
| Static Web Apps built-in CDN | **$0** | ✅ Simple | Dev/Testnet |
| AWS CloudFront + WAF | **$10-20** | 🟡 Moderate | Small Production |
| Cloudflare Pro | **$20 per domain** | ✅ Simple | Medium Production |
| Azure Front Door Standard | **$35-50** | ✅ Simple | Azure-Native Production |
| Azure Front Door Premium | **$330+** | 🟡 Moderate | Enterprise |

---

## Recommended Approach (Staged)

### Stage 1: Testnet (Current) - **FREE**
```bash
# Current configuration
enable_front_door = false

# Use Static Web Apps built-in CDN
# Cost: $0/month
```

### Stage 2: Small Production - **~$15/month**
```bash
# Option A: Add AWS CloudFront
# Deploy CloudFront distribution pointing to Azure Static Web Apps
# Add AWS WAF with managed rules
# Cost: ~$15/month

# Option B: Add Cloudflare Free
# Change DNS nameservers to Cloudflare
# Enable proxy for your domains
# Cost: $0/month (or $20/month for Pro)
```

### Stage 3: High Traffic Production - **~$40/month**
```bash
# Option A: Upgrade to Cloudflare Pro (2 domains)
# Cost: $40/month, unlimited bandwidth

# Option B: Enable Azure Front Door
enable_front_door = true
# Cost: ~$35-50/month
```

---

## How to Add CloudFront Later (No Azure Changes)

### Step 1: Deploy Current Config (Azure Only)
```bash
cd infrastructure/opentofu/azure
tofu apply -var-file=terraform.tfvars
# enable_front_door = false (already set)
```

### Step 2: Add AWS CloudFront (Future)
```bash
# Create aws/cloudfront.tf with configuration above
cd infrastructure/opentofu/aws
tofu apply

# Get CloudFront domain name
tofu output cloudfront_domain_name
```

### Step 3: Update DNS
```
# Instead of pointing to Azure directly:
chert.coin CNAME → xxxxx.cloudfront.net

# CloudFront forwards to Azure Static Web Apps
```

**No changes needed to Azure infrastructure!** CloudFront acts as a transparent proxy.

---

## My Recommendation for You

Given that you're using both AWS and Azure:

### For Now (Testnet)
**Use**: Static Web Apps built-in CDN (FREE)
```hcl
enable_front_door = false  # Already set
```
- Deploy and test everything
- No CDN costs while developing
- Basic DDoS protection included

### For Production Launch
**Use**: AWS CloudFront + WAF (~$15/month)
- Leverage your existing AWS infrastructure
- Much cheaper than Azure Front Door
- Better global coverage
- Easy to add later without changing Azure config

### Alternative: Cloudflare Free
If you want global CDN now without cost:
- Sign up for Cloudflare (free)
- Change DNS nameservers
- Enable proxy for both domains
- Get unlimited bandwidth + basic WAF
- Cost: $0/month

---

## Quick Decision Matrix

**Choose Static Web Apps built-in (FREE) if**:
- ✅ Testing/development
- ✅ Low traffic (<10k visitors/month)
- ✅ Not facing security threats
- ✅ Want simplest setup

**Choose AWS CloudFront (~$15/month) if**:
- ✅ Already using AWS
- ✅ Need WAF protection
- ✅ Want better global CDN
- ✅ Cost-conscious

**Choose Cloudflare ($0-20/month) if**:
- ✅ Want unlimited bandwidth
- ✅ Need DDoS protection
- ✅ Want easiest management
- ✅ Best value per dollar

**Choose Azure Front Door (~$35/month) if**:
- ✅ All-Azure infrastructure
- ✅ Need advanced Azure integration
- ✅ Want unified routing
- ✅ Enterprise requirements

---

## Bottom Line

**Save $35-50/month now** by disabling Front Door (already done in your config). Static Web Apps include free CDN that's perfectly fine for testnet/development.

**Add AWS CloudFront later** for ~$15/month when you go to production - much cheaper than Azure Front Door and better global coverage.

**Or use Cloudflare Free** ($0/month) for unlimited bandwidth if you don't need advanced AWS WAF rules.

You can always upgrade to Azure Front Door later if you need tighter Azure integration - it's just changing `enable_front_door = true` and re-running `tofu apply`.
