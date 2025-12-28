variable "location" {
  description = "Azure region for state storage"
  type        = string
  default     = "australiaeast"
}

variable "storage_account_name" {
  description = "Name of storage account for Terraform state (must be globally unique)"
  type        = string
  default     = "silicaterraformstate"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 characters, lowercase letters and numbers only."
  }
}
