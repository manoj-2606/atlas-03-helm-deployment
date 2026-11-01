terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.14"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  use_oidc = true
}

# -----------------------------------------------------------------------------
# atlas-infra-base module — provisions RG, VNet, AKS, ACR with cost tags
# Source: public GitHub repo (no credentials needed)
# -----------------------------------------------------------------------------
module "base" {
  source = "git::https://github.com/manoj-2606/atlas-infra-base.git"

  project_name           = var.project_name
  environment            = var.environment
  location               = var.location
  aks_node_count         = var.aks_node_count
  aks_node_size          = var.aks_node_size
  aks_kubernetes_version = var.kubernetes_version
  cost_center            = "atlas-platform"
  created_by             = "terraform"
}

# -----------------------------------------------------------------------------
# AcrPush role for the pipeline service principal
# The pipeline identity needs to push images to ACR.
# AKS already gets AcrPull via the base module.
# -----------------------------------------------------------------------------
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "pipeline_acr_push" {
  scope                = module.base.acr_id
  role_definition_name = "AcrPush"
  principal_id         = data.azurerm_client_config.current.object_id
}