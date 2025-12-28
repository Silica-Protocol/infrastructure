# ============================================================================
# Silica Testnet Infrastructure - Multi-Cloud Cost-Optimized
# ============================================================================
# 
# Target: 8 validator nodes (4 USA, 4 AUS region) + supporting services
# Goal: FREE to near-free hosting using cloud free tiers
#
# Cost Breakdown:
#   - Oracle Cloud: 4 ARM instances = FREE (Always Free tier)
#   - AWS Free Tier: 1 t3.micro (12 months) = FREE
#   - Azure Free Tier: 1 B1s (12 months) = FREE  
#   - Hetzner Cloud: 4x CX22 = ~€16/month (cheapest EU/AUS proxy)
#   - Fly.io: API/Monitoring = FREE tier
#
# Total Estimated Cost: €16-20/month (~$18-22 USD)
# ============================================================================

terraform {
  required_version = ">= 1.6"

  required_providers {
    # Oracle Cloud - Best free tier (4 ARM VMs, 24GB RAM, 200GB storage)
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
    # AWS - Free tier for supporting services
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Azure - Free tier backup
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    # Hetzner - Cheapest paid option (~€4/server)
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    # Cloudflare - Free CDN/DNS
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Use local backend for testnet (no cost)
  # For production, use S3/Azure Blob
  backend "local" {
    path = "terraform.tfstate"
  }
}

# ============================================================================
# Variables
# ============================================================================

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "testnet"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "silica"
}

# Oracle Cloud Variables
variable "oci_tenancy_ocid" {
  description = "Oracle Cloud tenancy OCID"
  type        = string
}

variable "oci_user_ocid" {
  description = "Oracle Cloud user OCID"
  type        = string
}

variable "oci_fingerprint" {
  description = "Oracle Cloud API key fingerprint"
  type        = string
}

variable "oci_private_key_path" {
  description = "Path to Oracle Cloud private key"
  type        = string
}

variable "oci_region" {
  description = "Oracle Cloud region (us-phoenix-1 for USA)"
  type        = string
  default     = "us-phoenix-1"
}

# Hetzner Variables
variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

# AWS Variables (for free tier services)
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

# Cloudflare Variables
variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for DNS"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for the network"
  type        = string
  default     = "silica.network"
}

# ============================================================================
# Local Variables
# ============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "opentofu"
  }

  # Node distribution
  # USA nodes: Oracle Cloud (Phoenix) - FREE
  # AUS-proxy nodes: Hetzner (Helsinki/Falkenstein) - €4/each
  # Note: Hetzner doesn't have AUS DC, but EU is closer than US-East
  
  validator_nodes = {
    # Oracle Cloud Free Tier - USA (4 nodes)
    "validator-0" = { provider = "oracle", region = "us-phoenix-1", zone = "AD-1" }
    "validator-1" = { provider = "oracle", region = "us-phoenix-1", zone = "AD-2" }
    "validator-2" = { provider = "oracle", region = "us-phoenix-1", zone = "AD-3" }
    "validator-3" = { provider = "oracle", region = "us-ashburn-1", zone = "AD-1" }
    
    # Hetzner Cloud - EU (closer to AUS than US-West) (4 nodes)
    "validator-4" = { provider = "hetzner", location = "hel1" }  # Helsinki
    "validator-5" = { provider = "hetzner", location = "hel1" }
    "validator-6" = { provider = "hetzner", location = "fsn1" }  # Falkenstein
    "validator-7" = { provider = "hetzner", location = "fsn1" }
  }
}

# ============================================================================
# Provider Configurations
# ============================================================================

provider "oci" {
  tenancy_ocid     = var.oci_tenancy_ocid
  user_ocid        = var.oci_user_ocid
  fingerprint      = var.oci_fingerprint
  private_key_path = var.oci_private_key_path
  region           = var.oci_region
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = local.common_tags
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ============================================================================
# Oracle Cloud Free Tier - 4 ARM Validator Nodes (USA)
# ============================================================================
# Oracle Cloud Always Free includes:
# - 4 Ampere A1 Compute instances (total: 24GB RAM, 4 OCPUs)
# - 200GB block storage
# - 10TB outbound data transfer
# ============================================================================

# Compartment for Silica resources
resource "oci_identity_compartment" "silica" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Silica Testnet Resources"
  name           = "${local.name_prefix}-compartment"
}

# VCN (Virtual Cloud Network)
resource "oci_core_vcn" "silica" {
  compartment_id = oci_identity_compartment.silica.id
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "${local.name_prefix}-vcn"
  dns_label      = "silica"
}

# Internet Gateway
resource "oci_core_internet_gateway" "silica" {
  compartment_id = oci_identity_compartment.silica.id
  vcn_id         = oci_core_vcn.silica.id
  display_name   = "${local.name_prefix}-igw"
  enabled        = true
}

# Route Table
resource "oci_core_route_table" "silica" {
  compartment_id = oci_identity_compartment.silica.id
  vcn_id         = oci_core_vcn.silica.id
  display_name   = "${local.name_prefix}-rt"

  route_rules {
    network_entity_id = oci_core_internet_gateway.silica.id
    destination       = "0.0.0.0/0"
  }
}

# Subnet for validators
resource "oci_core_subnet" "validators" {
  compartment_id    = oci_identity_compartment.silica.id
  vcn_id            = oci_core_vcn.silica.id
  cidr_block        = "10.0.1.0/24"
  display_name      = "${local.name_prefix}-validators"
  dns_label         = "validators"
  route_table_id    = oci_core_route_table.silica.id
  security_list_ids = [oci_core_security_list.validators.id]
}

# Security List for validators
resource "oci_core_security_list" "validators" {
  compartment_id = oci_identity_compartment.silica.id
  vcn_id         = oci_core_vcn.silica.id
  display_name   = "${local.name_prefix}-validators-sl"

  # Allow SSH
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # Allow API (8545)
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 8545
      max = 8545
    }
  }

  # Allow P2P (30300 UDP/TCP)
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 30300
      max = 30300
    }
  }
  
  ingress_security_rules {
    protocol = "17" # UDP
    source   = "0.0.0.0/0"
    udp_options {
      min = 30300
      max = 30300
    }
  }

  # Allow all egress
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

# Oracle Cloud ARM instances (FREE TIER)
# Each instance: 1 OCPU (ARM), 6GB RAM
resource "oci_core_instance" "validators" {
  for_each = {
    for k, v in local.validator_nodes : k => v
    if v.provider == "oracle"
  }

  compartment_id      = oci_identity_compartment.silica.id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "${local.name_prefix}-${each.key}"
  
  shape = "VM.Standard.A1.Flex" # ARM Ampere - FREE TIER
  
  shape_config {
    ocpus         = 1    # 1 OCPU per instance (4 total = free tier limit)
    memory_in_gbs = 6    # 6GB per instance (24GB total = free tier limit)
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu_arm.images[0].id
    boot_volume_size_in_gbs = 50 # 50GB per instance (200GB total = free tier)
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.validators.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = file("~/.ssh/id_rsa.pub")
    user_data = base64encode(templatefile("${path.module}/templates/cloud-init.yaml", {
      node_name    = each.key
      node_index   = index(keys(local.validator_nodes), each.key)
      environment  = var.environment
      domain       = var.domain_name
    }))
  }

  freeform_tags = local.common_tags
}

# Get Ubuntu ARM image for Oracle Cloud
data "oci_core_images" "ubuntu_arm" {
  compartment_id           = oci_identity_compartment.silica.id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Get availability domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.oci_tenancy_ocid
}

# ============================================================================
# Hetzner Cloud - 4 Validator Nodes (EU - closer to AUS)
# ============================================================================
# CX22: 2 vCPUs, 4GB RAM, 40GB NVMe, 20TB traffic = €4.15/month each
# Total: ~€16.60/month for 4 nodes
# ============================================================================

# SSH Key for Hetzner
resource "hcloud_ssh_key" "default" {
  name       = "${local.name_prefix}-ssh"
  public_key = file("~/.ssh/id_rsa.pub")
}

# Firewall for Hetzner validators
resource "hcloud_firewall" "validators" {
  name = "${local.name_prefix}-validators"

  # SSH
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # API
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "8545"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # P2P TCP
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "30300"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # P2P UDP  
  rule {
    direction = "in"
    protocol  = "udp"
    port      = "30300"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

# Hetzner CX22 instances (€4.15/month each)
resource "hcloud_server" "validators" {
  for_each = {
    for k, v in local.validator_nodes : k => v
    if v.provider == "hetzner"
  }

  name        = "${local.name_prefix}-${each.key}"
  server_type = "cx22"  # 2 vCPU, 4GB RAM, 40GB NVMe
  location    = each.value.location
  image       = "ubuntu-22.04"
  
  ssh_keys = [hcloud_ssh_key.default.id]
  
  firewall_ids = [hcloud_firewall.validators.id]

  user_data = templatefile("${path.module}/templates/cloud-init.yaml", {
    node_name    = each.key
    node_index   = index(keys(local.validator_nodes), each.key)
    environment  = var.environment
    domain       = var.domain_name
  })

  labels = local.common_tags
}

# ============================================================================
# Supporting Services (Free Tier)
# ============================================================================

# API Gateway / Load Balancer - Use Cloudflare (FREE)
# Monitoring - Use Fly.io (FREE tier) or self-hosted on Oracle
# Oracle - Run on one of the Oracle Cloud instances

# ============================================================================
# Cloudflare DNS (FREE)
# ============================================================================

resource "cloudflare_record" "validators" {
  for_each = merge(
    { for k, v in oci_core_instance.validators : k => v.public_ip },
    { for k, v in hcloud_server.validators : k => v.ipv4_address }
  )

  zone_id = var.cloudflare_zone_id
  name    = "${each.key}.${var.environment}"
  value   = each.value
  type    = "A"
  ttl     = 300
  proxied = false # Direct connection for P2P
}

# API endpoint (load balanced via Cloudflare)
resource "cloudflare_record" "api" {
  count = var.cloudflare_zone_id != "" ? 1 : 0
  
  zone_id = var.cloudflare_zone_id
  name    = "api.${var.environment}"
  value   = values(oci_core_instance.validators)[0].public_ip
  type    = "A"
  ttl     = 300
  proxied = true # Use Cloudflare CDN/DDoS protection
}

# ============================================================================
# Outputs
# ============================================================================

output "oracle_validators" {
  description = "Oracle Cloud validator instances"
  value = {
    for k, v in oci_core_instance.validators : k => {
      public_ip = v.public_ip
      private_ip = v.private_ip
    }
  }
}

output "hetzner_validators" {
  description = "Hetzner validator instances"
  value = {
    for k, v in hcloud_server.validators : k => {
      public_ip  = v.ipv4_address
      private_ip = v.ipv4_address
    }
  }
}

output "api_endpoint" {
  description = "API endpoint URL"
  value       = var.cloudflare_zone_id != "" ? "https://api.${var.environment}.${var.domain_name}" : "http://${values(oci_core_instance.validators)[0].public_ip}:8545"
}

output "cost_estimate" {
  description = "Estimated monthly cost"
  value = {
    oracle_cloud = "$0 (Always Free tier - 4 ARM instances)"
    hetzner      = "€16.60 (~$18 USD - 4x CX22)"
    cloudflare   = "$0 (Free tier)"
    total        = "~$18 USD/month"
  }
}
