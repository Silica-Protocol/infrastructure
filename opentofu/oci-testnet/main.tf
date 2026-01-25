terraform {
  required_version = ">= 1.6"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

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

variable "validator_count" {
  description = "Number of OCI validator nodes to provision (OCI Always Free supports up to 4 A1 instances)"
  type        = number
  default     = 4

  validation {
    condition     = var.validator_count >= 1 && var.validator_count <= 4
    error_message = "validator_count must be between 1 and 4 (inclusive) for OCI Always Free A1)."
  }
}

variable "instance_shape" {
  description = "OCI compute shape. Use VM.Standard.A1.Flex for ARM Always Free, or VM.Standard.E2.1.Micro for x86 Always Free (often has more capacity)."
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  description = "OCPUs for Flex shapes (ignored for fixed shapes)"
  type        = number
  default     = 1
}

variable "instance_memory_in_gbs" {
  description = "Memory (GB) for Flex shapes (ignored for fixed shapes)"
  type        = number
  default     = 6
}

variable "boot_volume_size_in_gbs" {
  description = "Boot volume size (GB)"
  type        = number
  default     = 50
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key to authorize on nodes"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "container_image" {
  description = "Container image reference for the Silica node (must be pullable by the instances). Example: ghcr.io/<owner>/<repo>:latest"
  type        = string
}

  variable "rpc_domain" {
    description = "Public DNS hostname used for the primary validator (validator-0) HTTPS RPC endpoint (Caddy)."
    type        = string
    default     = "testnet.silicaprotocol.network"
  }

# OCI auth/config
variable "oci_tenancy_ocid" {
  description = "Oracle Cloud tenancy OCID"
  type        = string

  validation {
    condition     = startswith(var.oci_tenancy_ocid, "ocid1.tenancy.")
    error_message = "oci_tenancy_ocid must be a tenancy OCID (starts with 'ocid1.tenancy.')."
  }
}

variable "oci_user_ocid" {
  description = "Oracle Cloud user OCID"
  type        = string

  validation {
    condition     = startswith(var.oci_user_ocid, "ocid1.user.")
    error_message = "oci_user_ocid must be a user OCID (starts with 'ocid1.user.')."
  }
}

variable "oci_fingerprint" {
  description = "Oracle Cloud API key fingerprint"
  type        = string

  validation {
    condition     = can(regex("^([0-9a-fA-F]{2}:){15}[0-9a-fA-F]{2}$", var.oci_fingerprint))
    error_message = "oci_fingerprint must look like an MD5 fingerprint (16 hex bytes separated by ':')."
  }
}

variable "oci_private_key_path" {
  description = "Path to Oracle Cloud private key"
  type        = string
}

variable "oci_region" {
  description = "Oracle Cloud region (e.g., us-phoenix-1)"
  type        = string
  default     = "us-phoenix-1"
}

variable "oci_compartment_ocid" {
  description = "Compartment OCID to deploy into (can be your tenancy/root compartment OCID)"
  type        = string

  validation {
    condition = startswith(var.oci_compartment_ocid, "ocid1.compartment.") || startswith(var.oci_compartment_ocid, "ocid1.tenancy.")
    error_message = "oci_compartment_ocid must be a compartment OCID (ocid1.compartment...) or the root compartment/tenancy OCID (ocid1.tenancy...)."
  }
}

variable "vcn_cidr" {
  description = "VCN CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "Subnet CIDR block"
  type        = string
  default     = "10.0.1.0/24"
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "opentofu"
  }

  ssh_public_key = file(pathexpand(var.ssh_public_key_path))

  is_flex_shape = endswith(var.instance_shape, ".Flex")

  validators = {
    for i in range(var.validator_count) :
    format("validator-%d", i) => {
      index = i
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.oci_tenancy_ocid
  user_ocid        = var.oci_user_ocid
  fingerprint      = var.oci_fingerprint
  private_key_path = pathexpand(var.oci_private_key_path)
  region           = var.oci_region
}

# Availability domains (some regions have fewer than 3)
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.oci_tenancy_ocid
}

resource "oci_core_vcn" "silica" {
  compartment_id = var.oci_compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${local.name_prefix}-vcn"
  dns_label      = "silica"
}

resource "oci_core_internet_gateway" "silica" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.silica.id
  display_name   = "${local.name_prefix}-igw"
  enabled        = true
}

resource "oci_core_route_table" "silica" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.silica.id
  display_name   = "${local.name_prefix}-rt"

  route_rules {
    network_entity_id = oci_core_internet_gateway.silica.id
    destination       = "0.0.0.0/0"
  }
}

resource "oci_core_security_list" "validators" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.silica.id
  display_name   = "${local.name_prefix}-validators-sl"

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 8545
      max = 8545
    }
  }

    # HTTP (Let's Encrypt / redirects)
    ingress_security_rules {
      protocol = "6" # TCP
      source   = "0.0.0.0/0"
      tcp_options {
        min = 80
        max = 80
      }
    }

    # HTTPS (primary validator RPC via Caddy)
    ingress_security_rules {
      protocol = "6" # TCP
      source   = "0.0.0.0/0"
      tcp_options {
        min = 443
        max = 443
      }
    }

  ingress_security_rules {
    protocol = "6" # TCP
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

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_subnet" "validators" {
  compartment_id    = var.oci_compartment_ocid
  vcn_id            = oci_core_vcn.silica.id
  cidr_block        = var.subnet_cidr
  display_name      = "${local.name_prefix}-validators"
  dns_label         = "validators"
  route_table_id    = oci_core_route_table.silica.id
  security_list_ids = [oci_core_security_list.validators.id]
}

# Ubuntu ARM image (A1)
data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.oci_compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "validators" {
  for_each = local.validators

  compartment_id = var.oci_compartment_ocid

  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[
    each.value.index % length(data.oci_identity_availability_domains.ads.availability_domains)
  ].name

  display_name = "${local.name_prefix}-${each.key}"

  shape = var.instance_shape

  dynamic "shape_config" {
    for_each = local.is_flex_shape ? [1] : []
    content {
      ocpus         = var.instance_ocpus
      memory_in_gbs = var.instance_memory_in_gbs
    }
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_arm.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.validators.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = local.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/templates/cloud-init.yaml", {
      node_name       = each.key
      node_index      = each.value.index
      environment     = var.environment
      rpc_domain      = var.rpc_domain
      ssh_public_key  = local.ssh_public_key
      container_image = var.container_image

      # Only validator-0 should terminate TLS for the shared hostname to avoid ACME conflicts.
      caddy_write_files = each.value.index == 0 ? (<<-EOT
  - path: /opt/silica/caddy/Caddyfile
    permissions: '0644'
    owner: root:root
    content: |
      {
        # Optional: set a contact email for Let's Encrypt.
        # email you@example.com
      }

      ${var.rpc_domain} {
        encode gzip
        reverse_proxy validator:8545
      }
EOT
) : ""

      caddy_compose_service = each.value.index == 0 ? (<<-EOT
        caddy:
          image: caddy:2.8
          container_name: silica-caddy
          restart: unless-stopped
          ports:
            - "80:80"
            - "443:443"
          volumes:
            - ./caddy/Caddyfile:/etc/caddy/Caddyfile:ro
            - ./caddy/data:/data
            - ./caddy/config:/config
          depends_on:
            - validator
EOT
) : ""

      ufw_api_rules = each.value.index == 0 ? (<<-EOT
      ufw allow 80/tcp
      ufw allow 443/tcp
EOT
) : ""
    }))
  }

  lifecycle {
    # OCI instances cannot apply updated cloud-init to existing VMs.
    # Ignoring user_data changes prevents forced replacement (and public IP churn)
    # during iterative infra tweaks.
    ignore_changes = [metadata["user_data"]]
  }

  freeform_tags = local.common_tags
}

output "oci_validators" {
  description = "OCI validator instances"
  value = {
    for k, v in oci_core_instance.validators : k => {
      public_ip  = v.public_ip
      private_ip = v.private_ip
    }
  }
}
