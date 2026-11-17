variable "subscription_id" {
  description = "ID da assinatura Azure for Students (az account show --query id -o tsv)"
  type        = string
}

variable "prefixo" {
  description = "Prefixo dos recursos e do endereço público"
  type        = string
  default     = "calcada-segura"
}

variable "location" {
  description = "Região da Azure. A conta Azure for Students só permite southcentralus, eastus2, northcentralus, chilecentral e canadacentral (brazilsouth é bloqueada)."
  type        = string
  default     = "northcentralus"
}

variable "vm_size" {
  description = "Tamanho da VM (B2als_v2 = 2 vCPU, 4 GiB). B1ms e B2s estão sem capacidade nas regiões da conta."
  type        = string
  default     = "Standard_B2als_v2"
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Caminho da sua chave pública SSH"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "admin_ip_cidr" {
  description = "SEU IP público com /32 (curl ifconfig.me). Só ele acessa a porta 22."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_ip_cidr, 0)) && !contains(["0.0.0.0/0", "*", "Internet", "Any"], var.admin_ip_cidr)
    error_message = "Informe um CIDR específico (ex.: 200.100.50.25/32). A porta de administração nunca pode ser aberta para 0.0.0.0/0."
  }
}

variable "api_image" {
  description = "Imagem publicada pelo pipeline, em minúsculas (ex.: ghcr.io/calcada-segura/calcada-segura-app:latest)"
  type        = string
}

variable "acme_email" {
  description = "E-mail para o certificado HTTPS (Let's Encrypt)"
  type        = string
}
