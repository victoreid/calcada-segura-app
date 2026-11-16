output "url_mvp" {
  description = "URL pública do MVP (vai na Ficha Técnica e no PDF)"
  value       = "https://${local.dominio}"
}

output "ip_publico" {
  value = azurerm_public_ip.ip.ip_address
}

output "ssh" {
  description = "Acesso de administração (só funciona a partir do admin_ip_cidr)"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.ip.ip_address}"
}

output "api_key" {
  description = "Chave X-API-Key para Robô, Visão e RPA (terraform output -raw api_key)"
  value       = random_password.api_key.result
  sensitive   = true
}

output "metrics_password" {
  description = "Senha do usuário 'prometheus' em /metrics (terraform output -raw metrics_password)"
  value       = random_password.metrics.result
  sensitive   = true
}
