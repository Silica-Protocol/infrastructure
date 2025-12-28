# Silica Infrastructure - Cost Comparison & Recommendations

## 🎯 Your Requirements

| Requirement | Solution |
|-------------|----------|
| 8 validator nodes | 4 USA + 4 AUS-region |
| Oracle service | Runs on validator node |
| API backend | Cloudflare-proxied to validators |
| Monitoring | Self-hosted (Prometheus/Grafana) |
| Cost | FREE to near-free |

---

## 💰 Cost Comparison

### Option 1: Maximum Free (Recommended for Testnet)

| Provider | Resources | Monthly Cost |
|----------|-----------|--------------|
| **Oracle Cloud** | 4x ARM instances (24GB RAM total) | **$0** |
| **Hetzner** | 4x CX22 (2vCPU, 4GB each) | **€16.60** |
| **Cloudflare** | DNS, CDN, DDoS | **$0** |
| | **TOTAL** | **~$18/month** |

**Specs per node:**
- Oracle: 1 OCPU ARM, 6GB RAM, 50GB disk
- Hetzner: 2 vCPU Intel, 4GB RAM, 40GB NVMe

### Option 2: All-Free (Maximum Cost Savings)

| Provider | Resources | Monthly Cost |
|----------|-----------|--------------|
| **Oracle Cloud** | 4x ARM instances (USA) | **$0** |
| **Azure Free** | 1x B1s (12 months) | **$0** |
| **AWS Free** | 1x t2.micro (12 months) | **$0** |
| **GCP Free** | 1x e2-micro (Always Free) | **$0** |
| **Cloudflare** | DNS, CDN | **$0** |
| | **TOTAL** | **$0/month** |

⚠️ **Limitations:**
- Only 4 reliable nodes (Oracle)
- Other free tiers = minimal resources (512MB-1GB RAM)
- Not suitable for production

### Option 3: Production (AWS + Azure)

| Provider | Resources | Monthly Cost |
|----------|-----------|--------------|
| **AWS** | 4x t3.small (2vCPU, 2GB) | ~$60 |
| **Azure** | 4x B2s (2vCPU, 4GB) | ~$120 |
| **Cloudflare** | DNS, CDN | **$0** |
| | **TOTAL** | **~$180/month** |

### Option 4: Production with Spot Instances

| Provider | Resources | Monthly Cost |
|----------|-----------|--------------|
| **AWS** | 4x t3.small spot (~70% off) | ~$18 |
| **Azure** | 4x B2s spot (~60% off) | ~$48 |
| **Cloudflare** | DNS, CDN | **$0** |
| | **TOTAL** | **~$66/month** |

⚠️ Spot instances can be interrupted - not ideal for validators

---

## 🖥️ Minimum Specs for Silica

Based on our testing:

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **CPU** | 1 vCPU | 2 vCPU |
| **RAM** | 2 GB | 4 GB |
| **Storage** | 20 GB | 50 GB |
| **Network** | 100 Mbps | 1 Gbps |

**For 8 nodes total:**
- Minimum: 8 vCPU, 16 GB RAM, 160 GB storage
- Recommended: 16 vCPU, 32 GB RAM, 400 GB storage

---

## 🏗️ Recommended Architecture

### Testnet (Your Current Need)

```
┌─────────────────────────────────────────────────────────────┐
│                      CLOUDFLARE (FREE)                       │
│                   DNS + CDN + DDoS Protection                │
└─────────────────────────────┬───────────────────────────────┘
                              │
        ┌─────────────────────┴─────────────────────┐
        │                                           │
┌───────┴───────┐                         ┌────────┴────────┐
│ ORACLE CLOUD  │                         │  HETZNER CLOUD  │
│  (FREE TIER)  │                         │  (~€16/month)   │
│               │                         │                 │
│ ┌───────────┐ │                         │ ┌─────────────┐ │
│ │Validator 0│ │ Phoenix, AZ             │ │ Validator 4 │ │ Helsinki
│ │Validator 1│ │                         │ │ Validator 5 │ │
│ │Validator 2│ │                         │ │ Validator 6 │ │ Falkenstein
│ │Validator 3│ │ Ashburn, VA             │ │ Validator 7 │ │
│ └───────────┘ │                         │ └─────────────┘ │
│               │                         │                 │
│ + Oracle      │                         │                 │
│ + API         │                         │                 │
│ + Monitoring  │                         │                 │
└───────────────┘                         └─────────────────┘
```

### Why This Setup?

1. **Oracle Cloud Free Tier** is the most generous:
   - 4 ARM Ampere instances (6GB RAM each!)
   - 200GB storage
   - 10TB outbound data
   - Truly "Always Free" - not 12-month trial

2. **Hetzner** is cheapest for EU servers:
   - €4.15/month per server
   - German company, GDPR compliant
   - Good network to Asia-Pacific

3. **Cloudflare** for free CDN/DNS:
   - Unlimited bandwidth
   - DDoS protection
   - Global edge network

---

## 📁 Infrastructure Files Created

```
infrastructure/opentofu/
├── testnet/
│   ├── main.tf                    # Testnet config (Oracle + Hetzner)
│   ├── terraform.tfvars.example   # Configuration template
│   └── templates/
│       └── cloud-init.yaml        # Node bootstrap script
│
└── production/
    ├── main.tf                    # Production config (AWS + Azure)
    └── templates/
        └── cloud-init.yaml        # Node bootstrap script
```

---

## 🚀 Quick Start - Testnet

### 1. Sign Up for Free Tiers

| Provider | Sign Up | Free Tier Details |
|----------|---------|-------------------|
| [Oracle Cloud](https://www.oracle.com/cloud/free/) | 2 min | 4 ARM VMs, 200GB, Always Free |
| [Hetzner](https://www.hetzner.com/cloud) | 2 min | €20 credit on signup |
| [Cloudflare](https://cloudflare.com) | 1 min | Free DNS, CDN, DDoS |

### 2. Get API Credentials

```bash
# Oracle Cloud
# 1. Profile -> Tenancy -> Copy OCID
# 2. Profile -> User Settings -> Copy User OCID
# 3. API Keys -> Generate API Key

# Hetzner
# Cloud Console -> Security -> API Tokens -> Generate

# Cloudflare
# Profile -> API Tokens -> Create Token
```

### 3. Configure & Deploy

```bash
cd infrastructure/opentofu/testnet

# Copy and edit config
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars

# Initialize
tofu init

# Preview
tofu plan

# Deploy
tofu apply
```

### 4. Configure Nodes

```bash
# SSH into each node
ssh silica@validator-0.testnet.silica.network

# Copy validator keys
scp keys/* silica@validator-0.testnet.silica.network:/opt/silica/keys/

# Start the node
sudo systemctl start silica
```

---

## 📊 Kubernetes Alternative

If you prefer Kubernetes, here are minimum specs:

### Managed K8s Costs

| Provider | Service | Control Plane | Min Workers | Total |
|----------|---------|---------------|-------------|-------|
| AWS EKS | EKS | $73/month | 2x t3.small = $30 | ~$103/month |
| Azure AKS | AKS | FREE | 2x B2s = $60 | ~$60/month |
| GCP GKE | Autopilot | ~$73/month | Included | ~$73/month |
| DigitalOcean | DOKS | $12/month | 2x $12 = $24 | ~$36/month |
| Linode | LKE | FREE | 2x $10 = $20 | ~$20/month |
| Vultr | VKE | FREE | 2x $10 = $20 | ~$20/month |

### K3s (Self-Managed) - Cheapest

Run K3s on your VMs for FREE Kubernetes:

```bash
# On first node (control plane)
curl -sfL https://get.k3s.io | sh -

# On worker nodes
curl -sfL https://get.k3s.io | K3S_URL=https://control-plane:6443 \
  K3S_TOKEN=$(ssh control-plane cat /var/lib/rancher/k3s/server/node-token) sh -
```

**Cost: $0 extra** - just your VM costs

---

## 🎯 My Recommendation

### For Testnet (Now)

**Use: Oracle Cloud + Hetzner = ~$18/month**

- 4 powerful ARM nodes for free (Oracle)
- 4 cheap EU nodes (Hetzner) 
- Cloudflare for DNS/CDN (free)
- No Kubernetes needed - Docker Compose is simpler

### For Production (Later)

**Use: AWS + Azure + Cloudflare = ~$180/month**

- Multi-cloud redundancy
- Geographic distribution (USA + AUS)
- Professional support available
- Consider reserved instances for 30-50% savings

---

## 📝 Notes on "AUS-ish" Location

Unfortunately, no major cloud provider offers truly free Australian servers:

| Option | Latency to Sydney | Cost |
|--------|-------------------|------|
| Oracle Singapore | ~60ms | $0 |
| Hetzner Helsinki | ~280ms | €4 |
| Vultr Sydney | ~1ms | $5 |
| AWS Sydney | ~1ms | $15+ |

**Recommendation:** For testnet, use Hetzner EU. For production, use Azure Australia East (Sydney).

---

## 🔧 Monitoring Stack (Free)

Include on one node:

```yaml
# docker-compose.monitoring.yml
services:
  prometheus:
    image: prom/prometheus:latest
    ports: ["9090:9090"]
    
  grafana:
    image: grafana/grafana:latest
    ports: ["3000:3000"]
    
  loki:
    image: grafana/loki:latest
    ports: ["3100:3100"]
```

Or use free hosted options:
- Grafana Cloud Free: 10K metrics, 50GB logs
- Better Stack Free: 1GB logs/month
- Axiom Free: 500GB/month

---

## Summary

| Scenario | Provider Mix | Monthly Cost |
|----------|--------------|--------------|
| **Testnet (Recommended)** | Oracle + Hetzner + Cloudflare | **~$18** |
| **All Free (Limited)** | Oracle + AWS/Azure/GCP Free | **$0** |
| **Production** | AWS + Azure + Cloudflare | **~$180** |
| **Production (Spot)** | AWS + Azure Spot | **~$66** |
