
# Working hub with load balancer. Single VNet, with 2 spokes. 
# 1 VM on each spoke, running nginx

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

# Hub VNet
resource "azurerm_virtual_network" "hub_vnet" {
  name                = "hub-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Subnet for Load Balancer
resource "azurerm_subnet" "lb_subnet" {
  name                 = "lb-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}


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




#----------------------------------------------------------------------------
# Load Balancer stuff
#----------------------------------------------------------------------------

# Public IP for Load Balancer
resource "azurerm_public_ip" "lb_public_ip" {
  name                = "lb-public-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Load Balancer
resource "azurerm_lb" "hub_lb" {
  name                = "hub-lb"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "lb-frontend"
    public_ip_address_id = azurerm_public_ip.lb_public_ip.id
  }
}

# Backend Pool for Spoke VMs
resource "azurerm_lb_backend_address_pool" "lb_backend_pool" {
  loadbalancer_id = azurerm_lb.hub_lb.id
  name            = "lb-backend-pool"
}

# Health Probe
resource "azurerm_lb_probe" "lb_health_probe" {
  loadbalancer_id = azurerm_lb.hub_lb.id
  name            = "http-probe"
  port            = 80
  protocol        = "Http"
  request_path    = "/"
}

# Load Balancing Rule
resource "azurerm_lb_rule" "lb_rule" {
  loadbalancer_id                = azurerm_lb.hub_lb.id
  name                           = "http-rule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "lb-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.lb_backend_pool.id]
  probe_id                       = azurerm_lb_probe.lb_health_probe.id
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

resource "azurerm_subnet_network_security_group_association" "lb_subnet" {
  subnet_id                 = azurerm_subnet.lb_subnet.id
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
# VM Stuff
#----------------------------------------------------------------------------

# VM in Spoke A
resource "azurerm_linux_virtual_machine" "vm_a1" {
  name                = "vm-a1"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_D2_v5"
  zone                = 1
  admin_username      = "adminuser"
  network_interface_ids = [azurerm_network_interface.vm_a1_nic.id]
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
  custom_data = filebase64("./data/cloud-init-spoke-a.yml")
}

# VM in Spoke B
resource "azurerm_linux_virtual_machine" "vm_b1" {
  name                = "vm-b1"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_D2_v5"
  zone                = 1
  admin_username      = "adminuser"
  network_interface_ids = [azurerm_network_interface.vm_b1_nic.id]
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
  custom_data = filebase64("./data/cloud-init-spoke-b.yml")
}


# Public IP for VM in Spoke A
resource "azurerm_public_ip" "vm_a1_public_ip" {
  name                = "vm-a1-public-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Update NIC for VM in Spoke A (now in hub_vnet)
resource "azurerm_network_interface" "vm_a1_nic" {
  name                = "vm-a1-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.lb_subnet.id  # Use a subnet in hub_vnet
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_a1_public_ip.id
  }
}

# Update NIC for VM in Spoke B (now in hub_vnet)
resource "azurerm_network_interface" "vm_b1_nic" {
  name                = "vm-b1-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.lb_subnet.id  # Use a subnet in hub_vnet
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_backend_address_pool_association" "vm_a1_lb" {
  network_interface_id    = azurerm_network_interface.vm_a1_nic.id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.lb_backend_pool.id
}

resource "azurerm_network_interface_backend_address_pool_association" "vm_b1_lb" {
  network_interface_id    = azurerm_network_interface.vm_b1_nic.id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.lb_backend_pool.id
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


# Output LB public IP
output "lb_public_ip" {
  value = azurerm_public_ip.lb_public_ip.ip_address  
  description = "Azure LB Public IP"
}
