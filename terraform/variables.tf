variable "location" {
  description = "Azure region for the resources"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-sample-node"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    environment = "dev"
    project     = "sample-node"
  }
}

variable "vnet_name" {
  description = "Virtual network name"
  type        = string
  default     = "vnet-sample-node"
}

variable "vnet_address_space" {
  description = "Virtual network address space"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_name" {
  description = "Subnet name for the Container Apps environment"
  type        = string
  default     = "subnet-container-apps"
}

variable "subnet_address_prefix" {
  description = "Subnet address prefix"
  type        = string
  default     = "10.0.1.0/24"
}

variable "container_app_name" {
  description = "Name of the Azure Container App"
  type        = string
  default     = "sample-node-app"
}

variable "container_app_environment_name" {
  description = "Name of the Container Apps environment"
  type        = string
  default     = "cae-sample-node"
}

variable "container_image" {
  description = "Container image for the app"
  type        = string
  default     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

variable "container_target_port" {
  description = "Target port exposed by the app"
  type        = number
  default     = 80
}

variable "client_id" {
  description = "Azure AD application or user-assigned managed identity client ID used for OIDC auth"
  type        = string
  default     = null
}

variable "tenant_id" {
  description = "Azure tenant ID used for OIDC auth"
  type        = string
  default     = null
}

variable "subscription_id" {
  description = "Azure subscription ID used for OIDC auth"
  type        = string
  default     = null
}
