# Create Resource Group
resource "random_pet" "rg_name" {
  prefix = var.resource_group_name_prefix
}

resource "azurerm_resource_group" "rg" {
  location = var.resource_group_location
  name     = random_pet.rg_name.id
}

# Create Virtual Network
resource "azurerm_virtual_network" "vnet_a" {
  name                = "bastion-vnet-a"
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_virtual_network" "vnet_b" {
    name                = "bastion-vnet-b"
    address_space       = ["10.2.0.0/16"]
    location            = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
}

# add peering
resource "azurerm_virtual_network_peering" "a_to_b" {
    name                         = "vnet-a-to-vnet-b"
    resource_group_name          = azurerm_resource_group.rg.name
    virtual_network_name         = azurerm_virtual_network.vnet_a.name
    remote_virtual_network_id    = azurerm_virtual_network.vnet_b.id

    allow_virtual_network_access = true
    allow_forwarded_traffic      = false
    allow_gateway_transit        = false
    use_remote_gateways          = false

}
# mirror the above. Make sure to change the variables name/id from a to b
resource "azurerm_virtual_network_peering" "b_to_a" {
    name                         = "vnet-b-to-vnet-a"
    resource_group_name          = azurerm_resource_group.rg.name
    virtual_network_name         = azurerm_virtual_network.vnet_b.name
    remote_virtual_network_id    = azurerm_virtual_network.vnet_a.id

    allow_virtual_network_access = true
    allow_forwarded_traffic      = false
    allow_gateway_transit        = false
    use_remote_gateways          = false

}
# Create Subnet for Azure Bastion
resource "azurerm_subnet" "bastion_subnet" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet_a.name
  address_prefixes     = ["10.1.1.0/24"]
}

# Create Public IP for Azure Bastion
resource "azurerm_public_ip" "bastion_pip" {
  name                = "example-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create Azure Bastion Host
resource "azurerm_bastion_host" "bastion" {
  name                = "example-bastion"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion_subnet.id
    public_ip_address_id = azurerm_public_ip.bastion_pip.id
  }
}