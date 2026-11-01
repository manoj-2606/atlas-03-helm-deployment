# =============================================================================
# destroy.ps1 — Terraform destroy + backend RG delete + verification
# Called by: azure-pipelines-destroy.yml
# Auth: AzureCLI@2 (OIDC)
#
# Order matters:
#   1. terraform destroy (needs state file → backend must exist)
#   2. Delete backend RG (state no longer needed)
#   3. Verify both RGs are gone
# =============================================================================
param(
    [Parameter(Mandatory)][string]$TerraformDir,
    [Parameter(Mandatory)][string]$VarFile,
    [Parameter(Mandatory)][string]$BackendRG,
    [Parameter(Mandatory)][string]$BackendSA,
    [Parameter(Mandatory)][string]$BackendContainer,
    [Parameter(Mandatory)][string]$BackendKey,
    [Parameter(Mandatory)][string]$ProjectRG
)

$ErrorActionPreference = "Stop"
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " DESTROY: Full Teardown" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# --- Install Terraform ---
Write-Host "[1/5] Installing Terraform..."
$tfVersion = "1.9.8"
curl -sLo /tmp/tf.zip "https://releases.hashicorp.com/terraform/$tfVersion/terraform_${tfVersion}_linux_amd64.zip"
sudo unzip -o /tmp/tf.zip -d /usr/local/bin | Out-Null
rm /tmp/tf.zip

# --- OIDC auth ---
Write-Host "[2/5] Configuring OIDC..."
$env:ARM_USE_OIDC        = "true"
$env:ARM_CLIENT_ID       = $env:servicePrincipalId
$env:ARM_OIDC_TOKEN      = $env:idToken
$env:ARM_TENANT_ID       = $env:tenantId
$env:ARM_SUBSCRIPTION_ID = (az account show --query id -o tsv)

# --- Terraform destroy ---
Write-Host "[3/5] Terraform destroy..."
Push-Location $TerraformDir
terraform init `
    -backend-config="resource_group_name=$BackendRG" `
    -backend-config="storage_account_name=$BackendSA" `
    -backend-config="container_name=$BackendContainer" `
    -backend-config="key=$BackendKey" `
    -input=false

if ($LASTEXITCODE -ne 0) {
    Write-Host "  Init failed — state may not exist. Skipping destroy." -ForegroundColor Yellow
} else {
    terraform destroy -var-file=$VarFile -auto-approve -input=false
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Terraform destroy failed — will try manual RG delete" -ForegroundColor Yellow
    } else {
        Write-Host "  -> Terraform destroy complete" -ForegroundColor Green
    }
}
Pop-Location

# --- Delete backend RG ---
Write-Host "[4/5] Deleting backend resource group: $BackendRG"
$backendExists = az group exists --name $BackendRG -o tsv
if ($backendExists -eq "true") {
    az group delete --name $BackendRG --yes --no-wait
    Write-Host "  -> Delete initiated (async)" -ForegroundColor Green
} else {
    Write-Host "  -> Already gone" -ForegroundColor Yellow
}

# --- Verify cleanup ---
Write-Host "[5/5] Verifying cleanup..."
Start-Sleep -Seconds 10

$projectExists = az group exists --name $ProjectRG -o tsv
$backendStill  = az group exists --name $BackendRG -o tsv

Write-Host "  $ProjectRG : $(if ($projectExists -eq 'true') { 'STILL EXISTS' } else { 'DELETED' })"
Write-Host "  $BackendRG : $(if ($backendStill -eq 'true') { 'DELETING (async)' } else { 'DELETED' })"

if ($projectExists -eq "true") {
    Write-Host "`n  WARNING: Project RG still exists. Forcing delete..." -ForegroundColor Yellow
    az group delete --name $ProjectRG --yes --no-wait
}

Write-Host "`nDestroy complete. Verify in Azure Portal: Resource Groups -> confirm empty.`n" -ForegroundColor Green