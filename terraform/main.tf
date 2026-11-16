locals {
  tags = {
    projeto = "calcada-segura"
    curso   = "fiap-gs-2026-2"
    gerenciado_por = "terraform"
  }
  dns_label = "${var.prefixo}-${random_string.sufixo.result}"
  dominio   = "${local.dns_label}.${var.location}.cloudapp.azure.com"
}

resource "random_string" "sufixo" {
  length  = 5
  upper   = false
  special = false
}

# Segredos gerados pelo Terraform (ficam só no state, que não vai para o Git)
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "random_password" "api_key" {
  length  = 40
  special = false
}

resource "random_password" "metrics" {
  length  = 32
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefixo}"
  location = var.location
  tags     = local.tags
}

# ---------------- Rede ----------------
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.prefixo}"
  address_space       = ["10.20.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.20.1.0/24"]
}

# Porta 80/443 aberta para a Internet é intencional: é o site público do MVP.
# trivy:ignore:AVD-AZU-0047
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-${var.prefixo}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  # Porta de administração: somente o IP do administrador
  security_rule {
    name                       = "ssh-somente-admin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_ip_cidr
    destination_address_prefix = "*"
  }

  # Site público do MVP (HTTP só redireciona para HTTPS)
  security_rule {
    name                       = "web-publico"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
  # Todo o resto é bloqueado pela regra padrão DenyAllInBound da Azure.
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_public_ip" "ip" {
  name                = "pip-${var.prefixo}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = local.dns_label
  tags                = local.tags
}

resource "azurerm_network_interface" "nic" {
  name                = "nic-${var.prefixo}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  ip_configuration {
    name                          = "principal"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip.id
  }
}

# ---------------- VM ----------------
resource "azurerm_linux_virtual_machine" "vm" {
  name                            = "vm-${var.prefixo}"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.nic.id]
  tags                            = local.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
    compose_b64 = filebase64("${path.module}/../deploy/docker-compose.prod.yml")
    deploy_b64  = filebase64("${path.module}/../deploy/deploy.sh")
    caddy_b64 = base64encode(templatefile("${path.module}/../deploy/Caddyfile.tftpl", {
      dominio    = local.dominio
      acme_email = var.acme_email
    }))
    env_b64 = base64encode(join("\n", [
      "API_IMAGE=${lower(var.api_image)}",
      "POSTGRES_USER=calcada",
      "POSTGRES_PASSWORD=${random_password.db.result}",
      "POSTGRES_DB=calcada",
      "API_KEY=${random_password.api_key.result}",
      "CHAOS_ENABLED=true",
      "",
    ]))
    metrics_password = random_password.metrics.result
  }))
}
