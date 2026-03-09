# Input Variables for DocuMagic Terraform Configuration

variable "documagic_api_key" {
  description = "API key for DocuMagic"
  type        = string
}

variable "documagic_region" {
  description = "Region for DocuMagic services"
  type        = string
}

variable "documagic_environment" {
  description = "Environment for DocuMagic (e.g., production, staging)"
  type        = string
}

variable "db_instance_type" {
  description = "Instance type for the database"
  type        = string
}

variable "db_storage_size" {
  description = "Storage size for the database in GB"
  type        = number
}

variable "enable_logging" {
  description = "Enable logging for the infrastructure"
  type        = bool
  default     = false
}