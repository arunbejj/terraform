#############################################################################
# TERRAFORM CONFIG
#############################################################################

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.0"
    }

    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 1.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

#############################################################################
# VARIABLES
#############################################################################

variable "sec_resource_group_name" {
  type    = string
  default = "security"
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "vnet_cidr_range" {
  type    = string
  default = "10.1.0.0/16"
}

variable "sec_subnet_prefixes" {
  type    = list(string)
  default = ["10.1.0.0/24", "10.1.1.0/24"]
}

variable "sec_subnet_names" {
  type    = list(string)
  default = ["siem", "inspect"]
}

#############################################################################
# DATA
#############################################################################

data "azurerm_subscription" "current" {}

#############################################################################
# PROVIDERS
#############################################################################

provider "azurerm" {
  features {}
}

#############################################################################
# RESOURCES
#############################################################################

## NETWORKING ##

resource "azurerm_resource_group" "vnet_sec" {
  name     = var.sec_resource_group_name
  location = var.location
}

module "vnet-sec" {
  source              = "Azure/vnet/azurerm"
  version             = "~> 2.0"
  resource_group_name = azurerm_resource_group.vnet_sec.name
  vnet_name           = var.sec_resource_group_name
  address_space       = [var.vnet_cidr_range]
  subnet_prefixes     = var.sec_subnet_prefixes
  subnet_names        = var.sec_subnet_names
  nsg_ids             = {}

  tags = {
    environment = "security"
    costcenter  = "security"

  }

  depends_on = [azurerm_resource_group.vnet_sec]
}

## AZURE AD SP ##

resource "random_password" "vnet_peering" {
  length  = 16
  special = true
}

resource "azuread_application" "vnet_peering" {
  display_name = "vnet-peer"
}

resource "azuread_service_principal" "vnet_peering" {
  application_id = azuread_application.vnet_peering.application_id
}

resource "azuread_service_principal_password" "vnet_peering" {
  service_principal_id = azuread_service_principal.vnet_peering.id
  value                = random_password.vnet_peering.result
  end_date_relative    = "17520h"
}

resource "azurerm_role_definition" "vnet-peering" {
  name  = "allow-vnet-peering"
  scope = data.azurerm_subscription.current.id

  permissions {
    actions     = ["Microsoft.Network/virtualNetworks/virtualNetworkPeerings/write", "Microsoft.Network/virtualNetworks/peer/action", "Microsoft.Network/virtualNetworks/virtualNetworkPeerings/read", "Microsoft.Network/virtualNetworks/virtualNetworkPeerings/delete"]
    not_actions = []
  }

  assignable_scopes = [
    data.azurerm_subscription.current.id,
  ]
}

resource "azurerm_role_assignment" "vnet" {
  scope              = module.vnet-sec.vnet_id
  role_definition_id = azurerm_role_definition.vnet-peering.role_definition_resource_id
  principal_id       = azuread_service_principal.vnet_peering.id
}

