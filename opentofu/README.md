# OpenTofu Infrastructure Configuration

Multi-cloud infrastructure-as-code for Silica blockchain network.

## 💰 Cost Summary

| Environment | Providers | Monthly Cost |
|-------------|-----------|--------------|
| **Testnet** | Oracle Cloud + Hetzner + Cloudflare | **~$18** |
| **Production** | AWS + Azure + Cloudflare | **~$180** |

## Directory Structure

```
opentofu/
├── testnet/              # Cost-optimized testnet (~$18/month)
│   ├── main.tf           # Oracle Cloud + Hetzner + Cloudflare
│   ├── terraform.tfvars.example
│   └── templates/
│       └── cloud-init.yaml
│
├── production/           # Production (AWS + Azure)
│   ├── main.tf           # AWS + Azure + Cloudflare
│   └── templates/
│       └── cloud-init.yaml
│
├── aws/                  # Legacy AWS-only configuration
│   └── ...
│
├── azure/                # Legacy Azure-only configuration  
│   └── ...
│
├── INFRASTRUCTURE_GUIDE.md   # Detailed cost comparison
├── COST_OPTIMIZATION_GUIDE.md # CDN/WAF options
└── README.md
```

## 🚀 Quick Start (Testnet)

```bash
cd infrastructure/opentofu/testnet

# Configure credentials
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # Add Oracle, Hetzner, Cloudflare API keys

# Deploy
tofu init
tofu plan
tofu apply
```

See [INFRASTRUCTURE_GUIDE.md](INFRASTRUCTURE_GUIDE.md) for detailed setup.

## Deployment Strategy

### Multi-Cloud Architecture
- **Australia Shard**: 3 validator nodes deployed in Sydney (AWS: `ap-southeast-2`, Azure: `australiaeast`)
- **America Shard**: 3 validator nodes deployed in East US (Azure: `eastus`)
- **Worker Nodes**: Optional 1-4 worker nodes for additional processing capacity
- **Web Services**: Chert & Silica websites hosted on Azure Static Web Apps with Front Door CDN

### Azure Components

#### Blockchain Infrastructure (main.tf)
- **AKS**: Kubernetes cluster for validator/worker nodes
- **VNet**: Virtual network with public/private subnets
- **Storage**: Managed disks for persistent blockchain data

#### Web Services (web-services.tf)
- **Static Web Apps**: Chert (token site) and Silica (protocol docs)
- **Front Door**: Global CDN with WAF protection
- **Storage Account**: Blob storage for assets, backups, artifacts
- **Container Apps**: Future API hosting (when api/ is implemented)

### Shard Configuration
- **Total Validator Nodes**: 6 (3 per shard)
- **Consensus**: Each shard maintains independent consensus
- **Cross-Shard Communication**: Atomic transactions with two-phase commit protocol

## Usage

### Prerequisites
1. Install [OpenTofu](https://opentofu.org/)
2. Configure cloud provider credentials
3. Install required providers:
   ```bash
   tofu init
   ```

### AWS Deployment
```bash
cd infrastructure/opentofu/aws
tofu init
tofu plan -var-file=terraform.tfvars
tofu apply -var-file=terraform.tfvars
```

### Azure Deployment
```bash
cd infrastructure/opentofu/azure
tofu init
tofu plan -var-file=terraform.tfvars
tofu apply -var-file=terraform.tfvars
```

For America shard deployment:
```bash
tofu plan -var-file=america-shard.tfvars
tofu apply -var-file=america-shard.tfvars
```

### Website Deployment

See [WEB_DEPLOYMENT_GUIDE.md](azure/WEB_DEPLOYMENT_GUIDE.md) for detailed instructions on:
- Deploying Chert and Silica websites to Azure Static Web Apps
- Configuring custom domains and SSL certificates
- Setting up Front Door CDN and WAF
- Uploading assets to Azure Blob Storage
- GitHub Actions integration for CI/CD

## Configuration Variables

### Common Variables (Both Clouds)
- `project_name`: Project identifier (default: "chert")
- `environment`: Deployment environment (dev, testnet, mainnet)
- `network_name`: Blockchain network name (default: "silica")
- `validator_node_count`: Number of validator nodes per shard (default: 3)
- `worker_node_count`: Number of worker nodes (default: 0)
- `container_image`: Docker image for Silica nodes

### AWS-Specific Variables
- `aws_region`: AWS region (Australia: "ap-southeast-2")
- `node_instance_type`: EC2 instance type (default: "t3.medium")
- `node_storage_size`: EBS volume size in GB (default: 100)

### Azure-Specific Variables
- `azure_region`: Azure region (Australia: "australiaeast", America: "eastus")
- `node_vm_size`: VM size (default: "Standard_D4s_v3")
- `node_disk_size`: Managed disk size in GB (default: 100)
- `kubernetes_version`: AKS Kubernetes version (default: "1.28")

## Node Specifications

### Validator Nodes
- **AWS**: t3.medium (2 vCPUs, 4GB RAM) + 100GB gp3 storage
- **Azure**: Standard_D4s_v3 (4 vCPUs, 16GB RAM) + 100GB Premium_LRS storage
- **Container**: 1-4 vCPUs, 2-16GB RAM

### Worker Nodes (Optional)
- Same specifications as validator nodes
- Can be deployed to either or both clouds
- Configurable count (1-4 nodes)

## Network Architecture

### AWS
- VPC with public/private subnets across 3 availability zones
- NAT gateways for private subnet internet access
- Security groups for database and application tiers

### Azure
- Virtual Network with public/private subnets
- NAT gateways for outbound internet access
- Network security groups with appropriate rules

## Monitoring and Logging
- **AWS**: CloudWatch integration with Prometheus
- **Azure**: Azure Monitor integration
- Both include comprehensive logging and monitoring

## Migration from Terraform

The OpenTofu configuration is a direct migration from the original Terraform code:
- All provider references updated from `hashicorp/*` to `opentofu/*`
- No functional changes - 100% compatible
- Same variable structure and output format

## Cross-Shard Communication

The infrastructure supports the sharding architecture with:
- Geographic distribution across continents
- Atomic cross-shard transactions
- Two-phase commit protocol for consistency
- Load balancing and failover capabilities

## Security Considerations

1. **Network Security**: Restrict `allowed_cidr_blocks` in production
2. **Encryption**: All storage uses encryption at rest
3. **Access Control**: Use cloud provider IAM/RBAC for access management
4. **Monitoring**: Enable comprehensive logging and monitoring

## Performance Targets

- **Single Shard**: 100K+ TPS
- **Global Network**: 1M+ TPS with cross-shard coordination
- **Latency**: <100ms cross-shard communication
- **Availability**: Multi-AZ deployment for high availability

## Next Steps

1. Test individual cloud deployments
2. Validate cross-shard communication
3. Implement monitoring and alerting
4. Configure backup and disaster recovery
5. Optimize performance based on workload