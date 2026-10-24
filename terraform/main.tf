resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

module "network" {
  source = "./modules/network"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  vnet_name           = var.vnet_name
  vnet_address_space  = var.vnet_address_space
  subnet_name         = var.subnet_name
  subnet_address_prefix = var.subnet_address_prefix
  tags                = var.tags
}

module "container_app" {
  source = "./modules/container_app"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  container_app_environment_name = var.container_app_environment_name
  container_app_name            = var.container_app_name
  subnet_id                    = module.network.subnet_id
  container_image              = var.container_image
  target_port                  = var.container_target_port
  tags                        = var.tags
}
