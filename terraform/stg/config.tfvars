location       = "eastus"
resource_group_name = "rg-sample-node"
vnet_name      = "vnet-sample-node"
vnet_address_space = "10.0.0.0/16"
subnet_name    = "subnet-container-apps"
subnet_address_prefix = "10.0.1.0/24"
container_app_name = "sample-node-app"
container_app_environment_name = "cae-sample-node"
container_image = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
container_target_port = 80

# Shared values for all envs
# client_id     = "<app-registration-client-id>"
# tenant_id     = "<tenant-id>"
# subscription_id = "<subscription-id>"
