resource "azurerm_log_analytics_workspace" "container_app" {
  name                = "law-${var.container_app_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_container_app_environment" "main" {
  name                       = var.container_app_environment_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.container_app.id
  infrastructure_subnet_id    = var.subnet_id
  tags                       = var.tags
}

resource "azurerm_container_app" "main" {
  name                         = var.container_app_name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  revision_mode               = "Single"
  tags                        = var.tags

  template {
    container {
      name   = "app"
      image  = var.container_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "PORT"
        value = tostring(var.target_port)
      }
    }

    min_replicas = 1
    max_replicas = 1
  }

  ingress {
    external_enabled = true
    target_port      = var.target_port
    transport        = "auto"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}
