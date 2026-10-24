output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "vnet_id" {
  value       = module.network.vnet_id
  description = "ID of the virtual network"
}

output "subnet_id" {
  value       = module.network.subnet_id
  description = "ID of the subnet used by the Container App environment"
}

output "container_app_url" {
  value       = module.container_app.container_app_url
  description = "Endpoint URL for the deployed Container App"
}

output "container_app_name" {
  value       = module.container_app.container_app_name
  description = "Name of the Container App"
}
