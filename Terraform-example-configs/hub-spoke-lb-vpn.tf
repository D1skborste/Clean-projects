

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
# Hub VNet and VM
#----------------------------------------------------------------------------

# Hub VNet
resource "azurerm_virtual_network" "hub_vnet" {
  name                = "hub-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Subnet for hub VM
resource "azurerm_subnet" "hub_subnet" {
  name                 = "hub-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Public IP for hub VM
resource "azurerm_public_ip" "hub_public_ip" {
  name                = "hub-public-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# NIC for hub VM
resource "azurerm_network_interface" "hub_nic" {
  name                = "hub-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.hub_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.hub_public_ip.id
  }
}

# hub VM
resource "azurerm_linux_virtual_machine" "hub_vm" {
  name                = "hub-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_D2_v5"
  admin_username      = "adminuser"
  network_interface_ids = [azurerm_network_interface.hub_nic.id]

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_rsa.pub")
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

  custom_data = filebase64("./data/cloud-init-hub.yml") # Put your on-prem private IP in .yml
}


#----------------------------------------------------------------------------
# Spoke A VNet and VM
#----------------------------------------------------------------------------

# Spoke VNet A
resource "azurerm_virtual_network" "vnet_a" {
  name                = "spoke-vnet-a"
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Subnet for VM_A
resource "azurerm_subnet" "vm_a_subnet" {
  name                 = "vm-a-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet_a.name
  address_prefixes     = ["10.1.1.0/24"]
}

# NIC for VM_A
resource "azurerm_network_interface" "vm_a_nic" {
  name                = "vm-a-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm_a_subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.1.1.4"
  }
}

# VM_A
resource "azurerm_linux_virtual_machine" "vm_a" {
  name                = "vm-a"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_D2_v5"
  admin_username      = "adminuser"
  network_interface_ids = [azurerm_network_interface.vm_a_nic.id]

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_rsa.pub")
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

  custom_data = filebase64("./data/cloud-init-vm-a.yml")
}


#----------------------------------------------------------------------------
# VNet Peering
#----------------------------------------------------------------------------

# Peer Hub to Spoke VNet A
resource "azurerm_virtual_network_peering" "hub_to_spoke_a" {
  name                         = "hub-to-spoke-a"
  resource_group_name          = azurerm_resource_group.rg.name
  virtual_network_name         = azurerm_virtual_network.hub_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.vnet_a.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
}

# Peer Spoke VNet A to Hub
resource "azurerm_virtual_network_peering" "spoke_a_to_hub" {
  name                         = "spoke-a-to-hub"
  resource_group_name          = azurerm_resource_group.rg.name
  virtual_network_name         = azurerm_virtual_network.vnet_a.name
  remote_virtual_network_id    = azurerm_virtual_network.hub_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
#  use_remote_gateways          = true  # Allows Spoke A to use Hub's VPN gateway
}


#----------------------------------------------------------------------------
# VPN Gateway
#----------------------------------------------------------------------------


# Subnet for VPN Gateway
resource "azurerm_subnet" "gateway_subnet" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["10.0.254.0/27"] # Changed to /27 as recommended for GatewaySubnet
}

# Public IP for VPN Gateway
resource "azurerm_public_ip" "vpn_gateway_ip" {
  name                = "vpn-gateway-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
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

# Associate route table with Hub subnets
resource "azurerm_subnet_route_table_association" "hub_subnet_route" {
  subnet_id      = azurerm_subnet.hub_subnet.id
  route_table_id = azurerm_route_table.vpn_route_table.id
}

# Associate route table with VNet A subnets (through gateway transit)
resource "azurerm_subnet_route_table_association" "vm_a_route" {
  subnet_id      = azurerm_subnet.vm_a_subnet.id
  route_table_id = azurerm_route_table.vpn_route_table.id
}


#----------------------------------------------------------------------------
# NSG Stuff
#----------------------------------------------------------------------------

# Associate NSGs with Subnets
resource "azurerm_subnet_network_security_group_association" "hub_subnet" {
  subnet_id                 = azurerm_subnet.hub_subnet.id
  network_security_group_id = azurerm_network_security_group.nsg_a.id
}

resource "azurerm_subnet_network_security_group_association" "vm_a_subnet" {
  subnet_id                 = azurerm_subnet.vm_a_subnet.id
  network_security_group_id = azurerm_network_security_group.nsg_a.id
}

# Network Security Groups
resource "azurerm_network_security_group" "nsg_a" {
  name                = "test-nsg-a"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowSSHFromVPN"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = "*" # Allow all, for testing
#    source_address_prefixes    = var.onprem_address_space # Only allow SSH from your on-premises network
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

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 1030
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "development"
  }
}


#----------------------------------------------------------------------------
# Outputs
#----------------------------------------------------------------------------

# Output the public IP addresses for SSH access
output "vm_public_ips" {
  value = {
    "hub_public_ip" = azurerm_public_ip.hub_public_ip.ip_address
#    "vm_a2_public_ip" = azurerm_public_ip.vm_a2_public_ip.ip_address
#    "vm_b1_public_ip" = azurerm_public_ip.vm_b1_public_ip.ip_address
#    "vm_b2_public_ip" = azurerm_public_ip.vm_b2_public_ip.ip_address
  }
  description = "Public IP addresses of all VMs for SSH access"
}

# Output the private IP addresses for the VMs
output "vm_private_ips" {
  value = {
    "hub_private_ip" = azurerm_network_interface.hub_nic.private_ip_address
    "vm_a_private_ip" = azurerm_network_interface.vm_a_nic.private_ip_address
#    "vm_b1_public_ip" = azurerm_public_ip.vm_b1_public_ip.ip_address
#    "vm_b2_public_ip" = azurerm_public_ip.vm_b2_public_ip.ip_address
  }
  description = "Private IP addresses of all VMs once VPN is good"
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
output "update_ipsec_secrets"{
  value = "${var.onprem_public_ip} ${azurerm_public_ip.vpn_gateway_ip.ip_address} : PSK '${var.vpn_shared_key}'" 
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
