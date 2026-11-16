terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # O state fica FORA do repositório (arquivo local ignorado pelo .gitignore).
  # Opcional: guardar o state num Storage Account da Azure. Descomente e rode
  # "terraform init -migrate-state" depois de criar o storage.
  # backend "azurerm" {
  #   resource_group_name  = "rg-tfstate"
  #   storage_account_name = "tfstatecalcada<sufixo>"
  #   container_name       = "tfstate"
  #   key                  = "calcada-segura.tfstate"
  # }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
