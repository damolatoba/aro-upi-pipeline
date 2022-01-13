terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
    }
    azuread = {
      source  = "hashicorp/azuread"
    }
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# Providers
# ----------------------------------------------------------------------------------------------------------------------

provider "azurerm" {
  features {}
}
provider "azuread" {
  # use_microsoft_graph = true
}

data "azurerm_subscription" "current" {}

data "azuread_client_config" "current" {}

# ----------------------------------------------------------------------------------------------------------------------
################################################## SERVICE PRINCIPAL ##################################################
# ----------------------------------------------------------------------------------------------------------------------
resource "azuread_application" "application" {
  display_name = var.app_reg_name
  owners       = [data.azuread_client_config.current.object_id]
}
resource "azuread_service_principal" "service_principal" {
  application_id               = azuread_application.application.application_id
  owners                       = [data.azuread_client_config.current.object_id]
  depends_on = [
    azuread_application.application
  ]
}
resource "azuread_service_principal_password" "principal_password" {
  service_principal_id = azuread_service_principal.service_principal.object_id
  depends_on = [
    azuread_service_principal.service_principal
  ]
}

# ----------------------------------------------------------------------------------------------------------------------
################################################## PRINCIPAL ROLE ASSIGNMENTS ##################################################
# ----------------------------------------------------------------------------------------------------------------------
resource "azurerm_role_assignment" "sp_assignment" {
  count			= length(var.principal_roles)
  scope			= data.azurerm_subscription.current.id
  role_definition_name	= var.principal_roles[count.index].role
  principal_id		= azuread_service_principal.service_principal.object_id
}

# ----------------------------------------------------------------------------------------------------------------------
# REQUIRE A SPECIFIC TERRAFORM VERSION OR HIGHER
# ----------------------------------------------------------------------------------------------------------------------
resource "azurerm_resource_group" "resource_group" {
  name     		= var.resource_group
  location 		= var.location
}

# ----------------------------------------------------------------------------------------------------------------------
# REQUIRE A SPECIFIC TERRAFORM VERSION OR HIGHER
# ----------------------------------------------------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "rg_identity" {
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location

  name = "rg-user-assigned-id"
}

# ----------------------------------------------------------------------------------------------------------------------
# REQUIRE A SPECIFIC TERRAFORM VERSION OR HIGHER
# ----------------------------------------------------------------------------------------------------------------------
resource "azurerm_role_assignment" "rg_id_assignment" {
  scope			= azurerm_resource_group.resource_group.id
  role_definition_name	= "Contributor"
  principal_id		= azurerm_user_assigned_identity.rg_identity.principal_id
}

# ----------------------------------------------------------------------------------------------------------------------
# REQUIRE A SPECIFIC TERRAFORM VERSION OR HIGHER
# ----------------------------------------------------------------------------------------------------------------------
resource "azurerm_storage_account" "primary" {
  name                     = "primarystorageaccnt"
  resource_group_name      = azurerm_resource_group.resource_group.name
  location                 = azurerm_resource_group.resource_group.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind = "Storage"
  min_tls_version = "TLS1_2"
  allow_blob_public_access = true
  network_rules {
    default_action             = "Allow"
    bypass = ["AzureServices"]
    ip_rules                   = []
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_storage_encryption_scope" "primary_storage" {
  name               = "microsoftmanaged"
  storage_account_id = azurerm_storage_account.primary.id
  source             = "Microsoft.Storage"
}
# ----------------------------------------------------------------------------------------------------------------------
# REQUIRE A SPECIFIC TERRAFORM VERSION OR HIGHER
# ----------------------------------------------------------------------------------------------------------------------
resource "azurerm_storage_container" "VHD_image_container" {
  name                  = "vhdcontainer"
  storage_account_name  = azurerm_storage_account.primary.name
  container_access_type = "private"

  depends_on		= [
    azurerm_storage_account.primary
  ]
}

# ----------------------------------------------------------------------------------------------------------------------
# REQUIRE A SPECIFIC TERRAFORM VERSION OR HIGHER
# ----------------------------------------------------------------------------------------------------------------------
resource "azurerm_storage_container" "bootstrap_ign_container" {
  name                  = "bstrapcontainer"
  storage_account_name  = azurerm_storage_account.primary.name
  container_access_type = "private"

  depends_on		= [
    azurerm_storage_account.primary
  ]
}

#copy vhd to blob storage module
# ----------------------------------------------------------------------------------------------------------------------
# REQUIRE A SPECIFIC TERRAFORM VERSION OR HIGHER
# ----------------------------------------------------------------------------------------------------------------------
resource "null_resource" "copy_vhd_to_blob" {
  provisioner "local-exec" {
    command = "./copy_vhd_to_blob.ps1"
    interpreter = ["PowerShell", "-Command"]
    environment = {
      # AZURE_SUBSCRIPTION_ID = var.subscription
      # AZURE_TENANT_ID = var.tenant
      # AZURE_CLIENT_ID = azuread_application.aro.application_id
      # AZURE_CLIENT_SECRET = nonsensitive(azuread_service_principal_password.aro.value)
      AZURE_RESOURCE_GROUP = var.resource_group
      PRIMARY_STORAGE_ACCOUNT = azurerm_storage_account.primary.name
      # AZURE_CLOUD_NAME = "AzurePublicCloud"
      # STORAGE_ID = azurerm_storage_account.backup_storage.id
      # CLUSTER_NAME = var.cluster_name
      # BLOB_CONTAINER = azurerm_storage_container.blob_container.name
      # CONTAINER_REGISTRY = azurerm_container_registry.acr.name
    }
  }

  depends_on		= [
    azurerm_storage_account.primary,
    azurerm_storage_container.VHD_image_container
  ]
}

# ----------------------------------------------------------------------------------------------------------------------
################################################## VNET AND SUBNETS ##################################################
# ----------------------------------------------------------------------------------------------------------------------
resource "azurerm_virtual_network" "vnet" {
  name                	= var.vnet_name
  resource_group_name 	= azurerm_resource_group.resource_group.name 
  location            	= azurerm_resource_group.resource_group.location
  address_space       	= [var.vnet_cidr]
}
resource "azurerm_subnet" "master_subnet" {
  name                 	= var.master_subnet_name
  virtual_network_name 	= azurerm_virtual_network.vnet.name
  resource_group_name  	= azurerm_resource_group.resource_group.name 
  address_prefixes 	= [var.master_subnet_cidr]
  service_endpoints = ["Microsoft.ContainerRegistry"]

  enforce_private_link_service_network_policies = true
}

resource "azurerm_subnet" "worker_subnet" {
  name                 	= var.worker_subnet_name
  virtual_network_name 	= azurerm_virtual_network.vnet.name
  resource_group_name  	= azurerm_resource_group.resource_group.name 
  address_prefixes 	= [var.worker_subnet_cidr]
  service_endpoints = ["Microsoft.ContainerRegistry"]
}

# ----------------------------------------------------------------------------------------------------------------------
################################################## PUBLIC IP ADDRESSES ##################################################
# ----------------------------------------------------------------------------------------------------------------------

resource "azurerm_public_ip" "master_pip" {
  name                = "masterpip1"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  allocation_method   = "Static"
  sku = "Standard"
}
resource "azurerm_public_ip" "internal_pip" {
  name                = "internalpip1"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  allocation_method   = "Static"
  sku = "Standard"
}

# ----------------------------------------------------------------------------------------------------------------------
################################################## LOADBALANCER EXTERNAL ##################################################
# ----------------------------------------------------------------------------------------------------------------------

resource "azurerm_lb" "public" {
  name                = "public-load-balancer"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  sku = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.master_pip.id
  }
}

resource "azurerm_lb_rule" "public_lb" {
  resource_group_name            = azurerm_resource_group.resource_group.name
  loadbalancer_id                = azurerm_lb.public.id
  name                           = "api-internal"
  protocol                       = "Tcp"
  frontend_port                  = 6443
  backend_port                   = 6443
  frontend_ip_configuration_name = "PublicIPAddress"
  load_distribution = "Default"
  idle_timeout_in_minutes = 30
}

resource "azurerm_lb_probe" "public_lb_probe" {
  resource_group_name = azurerm_resource_group.resource_group.name
  loadbalancer_id     = azurerm_lb.public.id
  name                = "api-internal-probe"
  protocol = "Https"
  port                = 6443
  request_path = "/readyz"
  interval_in_seconds = 10
  number_of_probes = 3
}

# ----------------------------------------------------------------------------------------------------------------------
################################################## LOADBALANCER INTERNAL ##################################################
# ----------------------------------------------------------------------------------------------------------------------

resource "azurerm_lb" "internal" {
  name                = "internal-load-balancer"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  sku = "Standard"

  frontend_ip_configuration {
    name                 = "internal-lb-ip"
    private_ip_address_allocation = "Dynamic"
    subnet_id = azurerm_subnet.master_subnet.id
    private_ip_address_version = "IPv4"
  }
}

resource "azurerm_lb_rule" "internal_lb_1" {
  resource_group_name            = azurerm_resource_group.resource_group.name
  loadbalancer_id                = azurerm_lb.internal.id
  name                           = "api-internal"
  protocol                       = "Tcp"
  frontend_port                  = 6443
  backend_port                   = 6443
  frontend_ip_configuration_name = "internal-lb-ip"
  load_distribution = "Default"
  idle_timeout_in_minutes = 30

  depends_on = [
    azurerm_lb.internal
  ]
}

resource "azurerm_lb_rule" "internal_lb_2" {
  resource_group_name            = azurerm_resource_group.resource_group.name
  loadbalancer_id                = azurerm_lb.internal.id
  name                           = "sint"
  protocol                       = "Tcp"
  frontend_port                  = 22623
  backend_port                   = 22623
  frontend_ip_configuration_name = "internal-lb-ip"
  load_distribution = "Default"
  idle_timeout_in_minutes = 30

  depends_on = [
    azurerm_lb.internal
  ]
}

resource "azurerm_lb_probe" "internal_probe_1" {
  resource_group_name = azurerm_resource_group.resource_group.name
  loadbalancer_id     = azurerm_lb.internal.id
  name                = "api-internal-probe"
  protocol = "Https"
  port                = 6443
  request_path = "/readyz"
  interval_in_seconds = 10
  number_of_probes = 3
}

resource "azurerm_lb_probe" "internal_probe_2" {
  resource_group_name = azurerm_resource_group.resource_group.name
  loadbalancer_id     = azurerm_lb.internal.id
  name                = "sint-probe"
  protocol = "Https"
  port                = 22623
  request_path = "/healthz"
  interval_in_seconds = 10
  number_of_probes = 3
}

# ----------------------------------------------------------------------------------------------------------------------
################################################## NETWORK SECURITY GROUPS ##################################################
# ----------------------------------------------------------------------------------------------------------------------
resource "azurerm_network_security_group" "net_security" {
  name                = "cluster-nsg"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  security_rule {
    name                       = "bootstrap_ssh_in"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# ----------------------------------------------------------------------------------------------------------------------
################################################## Azure Managed Disk ##################################################
# ----------------------------------------------------------------------------------------------------------------------
resource "azurerm_managed_disk" "masterOS_disk" {
  count			= var.number_of_master_nodes
  name                 = join("-", ["master-nic", (count.index)] ) #"acctestmd1"
  location             = azurerm_resource_group.resource_group.location
  resource_group_name  = azurerm_resource_group.resource_group.name
  storage_account_type = "Premium_LRS"
  tier = "P30"
  zones = [ "1" ]
  os_type = "Linux"
  hyper_v_generation = "V1"
  create_option        = "FromImage"
  image_reference_id = join("/", ["/Subscriptions", var.subscription, "Providers/Microsoft.Compute/Locations", var.location, "Publishers/azureopenshift/ArtifactTypes/VMImage/Offers/aro4/Skus/aro_48/Versions/48.84.20210630"])
  disk_size_gb         = 1024
  network_access_policy = "AllowAll"
}

resource "azurerm_managed_disk" "workerOS_disk" {
  count			= var.number_of_worker_nodes
  name                 = join("-", ["worker-nic", (count.index)] ) #"acctestmd2"
  location             = azurerm_resource_group.resource_group.location
  resource_group_name  = azurerm_resource_group.resource_group.name
  storage_account_type = "Premium_LRS"
  tier = "P30"
  zones = [ "1" ]
  os_type = "Linux"
  hyper_v_generation = "V1"
  create_option        = "FromImage"
  image_reference_id = join("/", ["/Subscriptions", var.subscription, "Providers/Microsoft.Compute/Locations", var.location, "Publishers/azureopenshift/ArtifactTypes/VMImage/Offers/aro4/Skus/aro_48/Versions/48.84.20210630"])
  disk_size_gb         = 128
  network_access_policy = "AllowAll"
}

# ----------------------------------------------------------------------------------------------------------------------
################################################## NETWORK INTERFACE CARDS ##################################################
# ----------------------------------------------------------------------------------------------------------------------
resource "azurerm_network_interface" "bootstrap_nic" {
  name                = "bootstrap-nic"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  dns_servers = []

  ip_configuration {
    name                          = "internalbootstrap"
    subnet_id                     = azurerm_subnet.master_subnet.id
    private_ip_address_allocation = "Dynamic"
    private_ip_address_version = "IPv4"
    primary = true
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# REQUIRE A SPECIFIC TERRAFORM VERSION OR HIGHER
# ----------------------------------------------------------------------------------------------------------------------
resource "azurerm_linux_virtual_machine" "bootstrap_node" {
  name                = "bootstrap-node"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  size                = "Standard_D2s_v3"
  disable_password_authentication = false
  admin_username      = "adminuser"
  admin_password = "adminpassword@01"
  network_interface_ids = [
    azurerm_network_interface.bootstrap_nic.id,
  ]

  os_disk {
    name = "bootstrap-disk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb = 100
  }

  source_image_reference {
    publisher = "RedHat"
    offer     = "RHEL"
    sku       = "8.1"
    version   = "latest"
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# REQUIRE A SPECIFIC TERRAFORM VERSION OR HIGHER
# ----------------------------------------------------------------------------------------------------------------------
resource "azurerm_network_interface" "master-nics" {
  count			= var.number_of_master_nodes
  name                = join("-", ["master-nic", (count.index)] )
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  dns_servers = []

  ip_configuration {
    name                          = join("-", ["Master-ip-config", (count.index)])
    subnet_id                     = azurerm_subnet.master_subnet.id
    private_ip_address_allocation = "Dynamic"
    private_ip_address_version = "IPv4"
    primary = true
  }
}
resource "azurerm_linux_virtual_machine" "master_nodes" {
  count = var.number_of_master_nodes
  name                = join("-", ["master-node", (count.index)] )
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  zone = 1
  size                = "Standard_D2s_v3"
  disable_password_authentication = false
  admin_username      = "adminuser"
  admin_password = "adminpassword@01"
  network_interface_ids = [
    azurerm_network_interface.master-nics[count.index].id,
  ]

  os_disk {
    name = join("-", ["master-disk", (count.index)] )
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "azureopenshift"
    offer     = "aro4"
    sku       = "aro_48"
    version   = "latest"
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# REQUIRE A SPECIFIC TERRAFORM VERSION OR HIGHER
# ----------------------------------------------------------------------------------------------------------------------
# resource "azurerm_network_interface" "worker-nics" {
#   count			= var.number_of_worker_nodes
#   name                = join("-", ["worker-nics", (count.index)] )
#   location            = azurerm_resource_group.resource_group.location
#   resource_group_name = azurerm_resource_group.resource_group.name

#   ip_configuration {
#     name                          = join("-", ["worker-ip-config", (count.index)])
#     subnet_id                     = azurerm_subnet.worker_subnet.id
#     private_ip_address_allocation = "Dynamic"
#   }
# }
# resource "azurerm_linux_virtual_machine" "worker_nodes" {
#   count = var.number_of_worker_nodes
#   name                = join("-", ["worker-node", (count.index)] )
#   resource_group_name = azurerm_resource_group.resource_group.name
#   location            = azurerm_resource_group.resource_group.location
#   size                = "Standard_D2s_v3"
#   disable_password_authentication = false
#   admin_username      = "adminuser"
#   admin_password = "adminpassword@01"
#   network_interface_ids = [
#     azurerm_network_interface.worker-nics[count.index].id,
#   ]

#   os_disk {
#     name = join("-", ["worker-disk", (count.index)] )
#     caching              = "ReadWrite"
#     storage_account_type = "Standard_LRS"
#   }

#   source_image_reference {
#     publisher = "RedHat"
#     offer     = "RHEL"
#     sku       = "8.1"
#     version   = "latest"
#   }
# }