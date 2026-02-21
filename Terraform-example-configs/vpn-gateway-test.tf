
# Create Resource Group
resource "random_pet" "rg_name" {
  prefix = var.resource_group_name_prefix
}

output "resource_group_name" {
    value = azurerm_resource_group.rg.name
}

resource "azurerm_resource_group" "rg" {
  location = var.resource_group_location
  name     = random_pet.rg_name.id
}


#----------------------------------------------------------------------------
# VNet stuff
#----------------------------------------------------------------------------

# Create Virtual Network
resource "azurerm_virtual_network" "vnet_a" {
  name                = "test-vnet-a"
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_virtual_network" "vnet_b" {
  name                = "test-vnet-b"
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
    allow_forwarded_traffic      = true
#    allow_forwarded_traffic      = false
    allow_gateway_transit        = true
#    allow_gateway_transit        = false
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


#----------------------------------------------------------------------------
# Subnet stuff
#----------------------------------------------------------------------------

# Subnets for VNet A
resource "azurerm_subnet" "vnet_a_subnet1" {
  name                 = "subnet-a1"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet_a.name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_subnet" "vnet_a_subnet2" {
  name                 = "subnet-a2"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet_a.name
  address_prefixes     = ["10.1.2.0/24"]
}

# Subnets for VNet B
resource "azurerm_subnet" "vnet_b_subnet1" {
  name                 = "subnet-b1"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet_b.name
  address_prefixes     = ["10.2.1.0/24"]
}

resource "azurerm_subnet" "vnet_b_subnet2" {
  name                 = "subnet-b2"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet_b.name
  address_prefixes     = ["10.2.2.0/24"]
}


#----------------------------------------------------------------------------
# VPN Stuff
#----------------------------------------------------------------------------

# Add Gateway Subnet for VPN (required for VPN Gateway)
resource "azurerm_subnet" "gateway_subnet" {
  name                 = "GatewaySubnet" # Must be 'GatewaySubnet¨
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet_a.name
#  address_prefixes     = ["10.1.254.0/24"] # Delete if /27 works
  address_prefixes     = ["10.1.254.0/27"] # Changed to /27 as recommended for GatewaySubnet
}

# VPN Gateway Public IP
resource "azurerm_public_ip" "vpn_gateway_ip" {
  name                = "vpn-gateway-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard" # Standard krävs för VpnGw1 och högre
}

# VPN Gateway
resource "azurerm_virtual_network_gateway" "vpn_gateway" {
  name                = "vpn-gateway"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  type     = "Vpn"
  vpn_type = "RouteBased"

  active_active = false
  enable_bgp    = false
  sku           = "VpnGw1"

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn_gateway_ip.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway_subnet.id
  }
}

# Local Network Gateway (represents your on-premises network)
resource "azurerm_local_network_gateway" "local_gateway" {
  name                = "local-network-gateway"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  gateway_address     = var.onprem_public_ip
  address_space       = var.onprem_address_space
}

# VPN Connection
resource "azurerm_virtual_network_gateway_connection" "vpn_connection" {
  name                = "vpn-connection-to-local"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpn_gateway.id
  local_network_gateway_id   = azurerm_local_network_gateway.local_gateway.id

  shared_key = var.vpn_shared_key

  enable_bgp = false   # Optional: Enable BGP if needed
  lifecycle {
    create_before_destroy = true # Force new connection if shared key changes
  }

}


#----------------------------------------------------------------------------
# Route Table for VPN traffic
#----------------------------------------------------------------------------

# Route Table for directing traffic to VPN gateway
resource "azurerm_route_table" "vpn_route_table" {
  name                = "vpn-route-table"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # Route for on-premise networks
  route {
    name           = "to-onprem-network1"
    address_prefix = "192.168.122.0/24"
    next_hop_type  = "VnetLocal"  # This will route through the VPN gateway
  }

  route {
    name           = "to-onprem-network2"
    address_prefix = "192.168.0.0/24"
    next_hop_type  = "VnetLocal"  # This will route through the VPN gateway
  }

  tags = {
    environment = "development"
    purpose     = "vpn-routing"
  }
}

# Associate route table with VNet A subnets
resource "azurerm_subnet_route_table_association" "vnet_a_subnet1_route" {
  subnet_id      = azurerm_subnet.vnet_a_subnet1.id
  route_table_id = azurerm_route_table.vpn_route_table.id
}

resource "azurerm_subnet_route_table_association" "vnet_a_subnet2_route" {
  subnet_id      = azurerm_subnet.vnet_a_subnet2.id
  route_table_id = azurerm_route_table.vpn_route_table.id
}

# Associate route table with VNet B subnets (through gateway transit)
resource "azurerm_subnet_route_table_association" "vnet_b_subnet1_route" {
  subnet_id      = azurerm_subnet.vnet_b_subnet1.id
  route_table_id = azurerm_route_table.vpn_route_table.id
}

resource "azurerm_subnet_route_table_association" "vnet_b_subnet2_route" {
  subnet_id      = azurerm_subnet.vnet_b_subnet2.id
  route_table_id = azurerm_route_table.vpn_route_table.id
}


#----------------------------------------------------------------------------
# NSG Stuff
#----------------------------------------------------------------------------

# Associate NSGs with Subnets
resource "azurerm_subnet_network_security_group_association" "nsg_a_subnet1" {
  subnet_id                 = azurerm_subnet.vnet_a_subnet1.id
  network_security_group_id = azurerm_network_security_group.nsg_a.id
}

resource "azurerm_subnet_network_security_group_association" "nsg_a_subnet2" {
  subnet_id                 = azurerm_subnet.vnet_a_subnet2.id
  network_security_group_id = azurerm_network_security_group.nsg_a.id
}
resource "azurerm_subnet_network_security_group_association" "nsg_b_subnet1" {
  subnet_id                 = azurerm_subnet.vnet_b_subnet1.id
  network_security_group_id = azurerm_network_security_group.nsg_a.id
}

resource "azurerm_subnet_network_security_group_association" "nsg_b_subnet2" {
  subnet_id                 = azurerm_subnet.vnet_b_subnet2.id
  network_security_group_id = azurerm_network_security_group.nsg_a.id
}

# Network Security Groups
resource "azurerm_network_security_group" "nsg_a" {
  name                = "test-nsg-a"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowICMP"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow traffic from local network
  security_rule {
    name                       = "AllowFromLocal"
    priority                   = 1020
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = var.onprem_address_space
    destination_address_prefix = "*"
  }

  tags = {
    environment = "development"
  }
}


#----------------------------------------------------------------------------
# VM Stuff
#----------------------------------------------------------------------------

# Virtual Machines
resource "azurerm_linux_virtual_machine" "vm_a1" {
  name                = "vm-a1"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_D2_v5"
  zone                = 1
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.vm_a1_nic.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_rsa.pub") # Replace with your SSH public key path
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

# Network Interfaces for VMs in VNet A
resource "azurerm_network_interface" "vm_a1_nic" {
  name                = "vm-a1-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vnet_a_subnet1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_a1_public_ip.id
  }
}

# Public IPs for VMs
resource "azurerm_public_ip" "vm_a1_public_ip" {
  name                = "vm-a1-public-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard" # Standard krävs för VpnGw1 och högre
}


#----------------------------------------------------------------------------
# Outputs
#----------------------------------------------------------------------------

# Output the public IP addresses for SSH access
output "vm_public_ips" {
  value = {
    "vm_a1_public_ip" = azurerm_public_ip.vm_a1_public_ip.ip_address
#    "vm_a2_public_ip" = azurerm_public_ip.vm_a2_public_ip.ip_address
#    "vm_b1_public_ip" = azurerm_public_ip.vm_b1_public_ip.ip_address
#    "vm_b2_public_ip" = azurerm_public_ip.vm_b2_public_ip.ip_address
  }
  description = "Public IP addresses of all VMs for SSH access"
}

# Output VPN Gateway IP
output "vpn_gateway_ip" {
  value       = azurerm_public_ip.vpn_gateway_ip.ip_address
  description = "Azure VPN Gateway public IP address"
}

# Output connection details
output "vpn_connection_details" {
  value = {
    azure_vpn_gateway_ip   = azurerm_public_ip.vpn_gateway_ip.ip_address
    local_network_cidr     = var.onprem_address_space
    shared_key             = "look in variables"
    connection_name        = azurerm_virtual_network_gateway_connection.vpn_connection.name
  }
}

output "instructions" {
  description = "Nästa steg"
  value = <<-EOT
    ======================================
    VPN Gateway skapad!
    ======================================

    Konfigurera din on-premise VPN-enhet med:

    1. Update /etc/ipsec.conf with Azure VPN Gateway IP: ${azurerm_public_ip.vpn_gateway_ip.ip_address}
    2. Update /etc/ipsec.secrets:
        ${var.onprem_public_ip} ${azurerm_public_ip.vpn_gateway_ip.ip_address} : PSK "Shared Key Set in Variables"
    3. bash: sudo ipsec up azure-vpn
    4. Remote network: ${join(", ", azurerm_virtual_network.vnet_a.address_space)}

    Verifiera anslutningen i Azure Portal:
    Virtual Network Gateway -> Connections -> ${azurerm_virtual_network_gateway_connection.vpn_connection.name}

    Status bör visa "Connected" när båda sidor är konfigurerade.
  EOT
}