variable "project_name" {
  description = "Project identifier used in resource naming"
  type        = string
  default     = "atlas-03"
}

variable "environment" {
  description = "Environment identifier (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "centralindia"
}

variable "aks_node_count" {
  description = "Number of nodes in the AKS system pool"
  type        = number
  default     = 1
}

variable "aks_node_size" {
  description = "VM SKU for AKS nodes (B2s = cheapest for non-prod)"
  type        = string
  default     = "Standard_B2s"
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS — check: az aks get-versions --location centralindia"
  type        = string
  default     = "1.30"
}