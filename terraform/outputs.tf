# Pass-through outputs from atlas-infra-base module
# Pipeline scripts read these to build, push, and deploy.

output "resource_group_name" {
  description = "Resource group name"
  value       = module.base.resource_group_name
}

output "aks_cluster_name" {
  description = "AKS cluster name — used by az aks get-credentials"
  value       = module.base.aks_cluster_name
}

output "acr_login_server" {
  description = "ACR login server URL (e.g., acratlas03dev.azurecr.io)"
  value       = module.base.acr_login_server
}

output "acr_name" {
  description = "ACR name — used by az acr login"
  value       = module.base.acr_name
}

output "kube_config_raw" {
  description = "Raw kubeconfig for kubectl/Helm access"
  value       = module.base.kube_config_raw
  sensitive   = true
}