# VPC and networking outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

# EKS cluster outputs
output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_iam_role_name" {
  description = "IAM role name associated with EKS cluster"
  value       = module.eks.cluster_iam_role_name
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN associated with EKS cluster"
  value       = module.eks.cluster_iam_role_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

# Node group outputs
output "node_group_arn" {
  description = "Amazon Resource Name (ARN) of the EKS Node Group"
  value       = module.eks.node_group_arn
}

output "node_group_status" {
  description = "Status of the EKS Node Group"
  value       = module.eks.node_group_status
}

# Load balancer outputs
output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = module.load_balancer.dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the load balancer"
  value       = module.load_balancer.zone_id
}

# Monitoring outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = module.monitoring.log_group_name
}

output "prometheus_endpoint" {
  description = "Prometheus server endpoint"
  value       = module.monitoring.prometheus_endpoint
  sensitive   = true
}

# Security outputs
output "kms_key_id" {
  description = "KMS key ID for encryption"
  value       = module.security.kms_key_id
}

output "secrets_manager_secret_arn" {
  description = "ARN of the secrets manager secret"
  value       = module.security.secrets_manager_secret_arn
  sensitive   = true
}

# Database outputs (if RDS is used for metadata)
output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.database.endpoint
  sensitive   = true
}

output "rds_port" {
  description = "RDS instance port"
  value       = module.database.port
}

# Backup outputs
output "backup_vault_arn" {
  description = "ARN of the backup vault"
  value       = module.backup.vault_arn
}

# Service discovery outputs
output "service_discovery_namespace_id" {
  description = "ID of the service discovery namespace"
  value       = module.service_discovery.namespace_id
}

output "service_discovery_namespace_arn" {
  description = "ARN of the service discovery namespace"
  value       = module.service_discovery.namespace_arn
}