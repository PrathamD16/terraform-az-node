terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}

  # Use either:
  # 1. GitHub OIDC via ARM_CLIENT_ID / ARM_TENANT_ID / ARM_SUBSCRIPTION_ID
  # 2. Managed Identity via az login --identity and ARM_SUBSCRIPTION_ID
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
}
