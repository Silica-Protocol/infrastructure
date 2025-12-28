# ============================================================================
# Silica Production Infrastructure - AWS + Azure Multi-Cloud
# ============================================================================
#
# Architecture:
#   - AWS: Primary infrastructure (USA nodes, API, monitoring)
#   - Azure: Secondary region (AUS nodes, backup services)
#   - Cloudflare: DNS, CDN, DDoS protection (FREE)
#
# Cost Optimization:
#   - Use spot/preemptible instances where possible
#   - Reserved instances for long-running validators
#   - Cloudflare for free CDN/WAF instead of CloudFront/Front Door
#
# ============================================================================

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {
    bucket         = "silica-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "silica-terraform-locks"
  }
}

# ============================================================================
# Variables
# ============================================================================

variable "environment" {
  type    = string
  default = "production"
}

variable "project_name" {
  type    = string
  default = "silica"
}

# AWS
variable "aws_region_primary" {
  type    = string
  default = "us-west-2"  # Oregon - good latency to both coasts
}

# Azure
variable "azure_region_primary" {
  type    = string
  default = "australiaeast"  # Sydney
}

variable "azure_subscription_id" {
  type      = string
  sensitive = true
}

# Cloudflare
variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_zone_id" {
  type = string
}

variable "domain_name" {
  type    = string
  default = "silica.network"
}

# Node configuration
variable "validator_count_aws" {
  type    = number
  default = 4
}

variable "validator_count_azure" {
  type    = number
  default = 4
}

variable "use_spot_instances" {
  description = "Use spot/preemptible instances for cost savings"
  type        = bool
  default     = false  # Set true for testnet, false for production
}

# ============================================================================
# Locals
# ============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "opentofu"
  }
  
  # Instance sizes - minimum viable for Silica
  aws_instance_type   = var.use_spot_instances ? "t3.small" : "t3.small"  # 2 vCPU, 2GB
  azure_instance_size = "Standard_B2s"  # 2 vCPU, 4GB
}

# ============================================================================
# Providers
# ============================================================================

provider "aws" {
  region = var.aws_region_primary
  
  default_tags {
    tags = local.common_tags
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ============================================================================
# AWS Infrastructure - USA Region (4 validators)
# ============================================================================

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# Subnets (multi-AZ for high availability)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  
  tags = {
    Name = "${local.name_prefix}-public-${count.index}"
    Type = "public"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  
  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Group for validators
resource "aws_security_group" "validators" {
  name_prefix = "${local.name_prefix}-validators-"
  vpc_id      = aws_vpc.main.id

  # SSH (restrict to your IP in production)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Restrict this!
  }

  # API
  ingress {
    from_port   = 8545
    to_port     = 8545
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # P2P
  ingress {
    from_port   = 30300
    to_port     = 30300
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 30300
    to_port     = 30300
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Metrics (internal only)
  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-validators-sg"
  }
}

# EC2 Instances for validators (AWS)
resource "aws_instance" "validators" {
  count         = var.validator_count_aws
  ami           = data.aws_ami.ubuntu.id
  instance_type = local.aws_instance_type
  subnet_id     = aws_subnet.public[count.index % length(aws_subnet.public)].id
  
  vpc_security_group_ids = [aws_security_group.validators.id]
  
  # Cost optimization: use spot instances for testnet
  # instance_market_options {
  #   market_type = "spot"
  #   spot_options {
  #     max_price = "0.02"  # ~50% savings
  #   }
  # }

  root_block_device {
    volume_size = 50  # GB
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/cloud-init.yaml", {
    node_name   = "validator-aws-${count.index}"
    node_index  = count.index
    environment = var.environment
    domain      = var.domain_name
    region      = "usa"
  }))

  tags = {
    Name = "${local.name_prefix}-validator-${count.index}"
    Role = "validator"
  }
}

# Get latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# ============================================================================
# Azure Infrastructure - Australia Region (4 validators)
# ============================================================================

resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg"
  location = var.azure_region_primary
  
  tags = local.common_tags
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-vnet"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.1.0.0/16"]
  
  tags = local.common_tags
}

resource "azurerm_subnet" "validators" {
  name                 = "validators"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.1.1.0/24"]
}

# Network Security Group
resource "azurerm_network_security_group" "validators" {
  name                = "${local.name_prefix}-validators-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "API"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8545"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "P2P-TCP"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "30300"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "P2P-UDP"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "30300"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = local.common_tags
}

# Public IPs for Azure validators
resource "azurerm_public_ip" "validators" {
  count               = var.validator_count_azure
  name                = "${local.name_prefix}-validator-${count.index}-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  
  tags = local.common_tags
}

# Network Interfaces
resource "azurerm_network_interface" "validators" {
  count               = var.validator_count_azure
  name                = "${local.name_prefix}-validator-${count.index}-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.validators.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.validators[count.index].id
  }
  
  tags = local.common_tags
}

resource "azurerm_network_interface_security_group_association" "validators" {
  count                     = var.validator_count_azure
  network_interface_id      = azurerm_network_interface.validators[count.index].id
  network_security_group_id = azurerm_network_security_group.validators.id
}

# Azure VMs
resource "azurerm_linux_virtual_machine" "validators" {
  count               = var.validator_count_azure
  name                = "${local.name_prefix}-validator-${count.index}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = local.azure_instance_size
  admin_username      = "silica"
  
  network_interface_ids = [azurerm_network_interface.validators[count.index].id]

  admin_ssh_key {
    username   = "silica"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/templates/cloud-init.yaml", {
    node_name   = "validator-azure-${count.index}"
    node_index  = count.index + var.validator_count_aws
    environment = var.environment
    domain      = var.domain_name
    region      = "australia"
  }))

  tags = merge(local.common_tags, {
    Role = "validator"
  })
}

# ============================================================================
# Cloudflare DNS & CDN (FREE)
# ============================================================================

# DNS records for AWS validators
resource "cloudflare_record" "validators_aws" {
  count   = var.validator_count_aws
  zone_id = var.cloudflare_zone_id
  name    = "validator-${count.index}"
  value   = aws_instance.validators[count.index].public_ip
  type    = "A"
  ttl     = 300
  proxied = false  # Direct connection for P2P
}

# DNS records for Azure validators
resource "cloudflare_record" "validators_azure" {
  count   = var.validator_count_azure
  zone_id = var.cloudflare_zone_id
  name    = "validator-${count.index + var.validator_count_aws}"
  value   = azurerm_public_ip.validators[count.index].ip_address
  type    = "A"
  ttl     = 300
  proxied = false
}

# API load balancing (round-robin via Cloudflare)
resource "cloudflare_record" "api" {
  count   = var.validator_count_aws
  zone_id = var.cloudflare_zone_id
  name    = "api"
  value   = aws_instance.validators[count.index].public_ip
  type    = "A"
  ttl     = 300
  proxied = true  # Use Cloudflare CDN + DDoS protection
}

# ============================================================================
# Outputs
# ============================================================================

output "aws_validators" {
  value = {
    for i, instance in aws_instance.validators : "validator-${i}" => {
      public_ip  = instance.public_ip
      private_ip = instance.private_ip
      region     = "usa"
    }
  }
}

output "azure_validators" {
  value = {
    for i, ip in azurerm_public_ip.validators : "validator-${i + var.validator_count_aws}" => {
      public_ip = ip.ip_address
      region    = "australia"
    }
  }
}

output "api_endpoint" {
  value = "https://api.${var.domain_name}"
}

output "cost_estimate_monthly" {
  value = {
    aws = {
      instances = "${var.validator_count_aws}x t3.small @ ~$15/month = ~$${var.validator_count_aws * 15}"
      storage   = "~$5"
      network   = "~$10 (depends on traffic)"
      total     = "~$${var.validator_count_aws * 15 + 15}"
    }
    azure = {
      instances = "${var.validator_count_azure}x B2s @ ~$30/month = ~$${var.validator_count_azure * 30}"
      storage   = "~$10"
      network   = "~$10"
      total     = "~$${var.validator_count_azure * 30 + 20}"
    }
    cloudflare = "$0 (free tier)"
    total_estimate = "~$${(var.validator_count_aws * 15 + 15) + (var.validator_count_azure * 30 + 20)}/month"
  }
}
