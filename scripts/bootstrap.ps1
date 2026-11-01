# =============================================================================
# bootstrap.ps1 — Creates Terraform backend storage (idempotent)
# =============================================================================
param(
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$StorageAccount,
    [Parameter(Mandatory)][string]$Container,
    [Parameter(Mandatory)][string]$Location
)

$ErrorActionPreference = "Stop"

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " BOOTSTRAP: Backend Storage" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    # --- Resource Group ---
    Write-Host "[1/3] Resource Group: $ResourceGroup"
    az group create --name $ResourceGroup --location $Location --output none
    if ($LASTEXITCODE -ne 0) { throw "Failed to create resource group" }
    Write-Host "  -> OK" -ForegroundColor Green

    # --- Storage Account ---
    Write-Host "[2/3] Storage Account: $StorageAccount"
    $exists = az storage account check-name --name $StorageAccount --query "nameAvailable" -o tsv
    if ($exists -eq "true") {
        az storage account create `
            --name $StorageAccount `
            --resource-group $ResourceGroup `
            --location $Location `
            --sku Standard_LRS `
            --kind StorageV2 `
            --allow-blob-public-access false `
            --output none
        if ($LASTEXITCODE -ne 0) { throw "Failed to create storage account" }
        Write-Host "  -> Created" -ForegroundColor Green
    } else {
        Write-Host "  -> Already exists" -ForegroundColor Yellow
    }

    # --- Blob Container ---
    Write-Host "[3/3] Blob Container: $Container"
    az storage container create `
        --name $Container `
        --account-name $StorageAccount `
        --auth-mode login `
        --output none 2>$null
    Write-Host "  -> OK" -ForegroundColor Green

    Write-Host "`nBackend storage ready.`n" -ForegroundColor Green
}
catch {
    # Write error context for log-error.ps1
    $errorContext = @{
        error      = $_.Exception.Message
        scriptLine = $_.InvocationInfo.ScriptLineNumber
        script     = "bootstrap.ps1"
    }
    $contextPath = Join-Path $env:BUILD_ARTIFACTSTAGINGDIRECTORY "error-context.json"
    $errorContext | ConvertTo-Json | Set-Content $contextPath -Force
    Write-Host "Error context saved to $contextPath" -ForegroundColor Red
    throw
}