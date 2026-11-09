# =============================================================================
# infra.ps1 — Terraform engine: init + plan + apply
# =============================================================================
param(
    [Parameter(Mandatory)][ValidateSet("plan", "apply")][string]$Action,
    [Parameter(Mandatory)][string]$TerraformDir,
    [Parameter(Mandatory)][string]$VarFile,
    [Parameter(Mandatory)][string]$BackendRG,
    [Parameter(Mandatory)][string]$BackendSA,
    [Parameter(Mandatory)][string]$BackendContainer,
    [Parameter(Mandatory)][string]$BackendKey
)

$ErrorActionPreference = "Stop"

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " INFRA: Terraform $($Action.ToUpper())" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    # --- Install Terraform ---
    Write-Host "[1/4] Installing Terraform 1.9.8..."
    $tfVersion = "1.9.8"
    curl -sLo /tmp/tf.zip "https://releases.hashicorp.com/terraform/$tfVersion/terraform_${tfVersion}_linux_amd64.zip"
    sudo unzip -o /tmp/tf.zip -d /usr/local/bin | Out-Null
    rm /tmp/tf.zip
    terraform version
    Write-Host "  -> OK" -ForegroundColor Green

    # --- OIDC auth ---
    Write-Host "[2/4] Configuring OIDC authentication..."
    $env:ARM_USE_OIDC        = "true"
    $env:ARM_CLIENT_ID       = $env:servicePrincipalId
    $env:ARM_OIDC_TOKEN      = $env:idToken
    $env:ARM_TENANT_ID       = $env:tenantId
    $env:ARM_SUBSCRIPTION_ID = (az account show --query id -o tsv)

    if (-not $env:ARM_OIDC_TOKEN) {
        throw "OIDC token not available. Ensure addSpnToEnvironment: true in pipeline task."
    }
    Write-Host "  -> Client: $($env:ARM_CLIENT_ID.Substring(0,8))..." -ForegroundColor Green

    # --- Terraform Init ---
    Write-Host "[3/4] Terraform init..."
    Push-Location $TerraformDir
    terraform init `
        -backend-config="resource_group_name=$BackendRG" `
        -backend-config="storage_account_name=$BackendSA" `
        -backend-config="container_name=$BackendContainer" `
        -backend-config="key=$BackendKey" `
        -input=false
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw "Terraform init failed" }
    Write-Host "  -> OK" -ForegroundColor Green

    Write-Host "VarFile: $VarFile" -ForegroundColor Yellow
    Write-Host "Exists: $(Test-Path $VarFile)" -ForegroundColor Yellow
    # --- Terraform Plan/Apply ---
    Write-Host "[4/4] Terraform $Action..."
    if ($Action -eq "plan") {
        $tfOutput = terraform plan "-var-file=$VarFile" -input=false -out=tfplan 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            $tfError = ($tfOutput -split "`n" | Where-Object { $_ -match "Error:" }) -join "; "
            if (-not $tfError) { $tfError = ($tfOutput -split "`n" | Select-Object -Last 5) -join "; " }
            Pop-Location
            throw "Terraform plan failed: $tfError"
        }
    } else {
        $tfOutput = terraform plan "-var-file=$VarFile" -input=false -out=tfplan 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            $tfError = ($tfOutput -split "`n" | Where-Object { $_ -match "Error:" }) -join "; "
            if (-not $tfError) { $tfError = ($tfOutput -split "`n" | Select-Object -Last 5) -join "; " }
            Pop-Location
            throw "Terraform plan failed: $tfError"
        }

        $tfOutput = terraform apply -input=false tfplan 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            $tfError = ($tfOutput -split "`n" | Where-Object { $_ -match "Error:" }) -join "; "
            if (-not $tfError) { $tfError = ($tfOutput -split "`n" | Select-Object -Last 5) -join "; " }
            Pop-Location
            throw "Terraform apply failed: $tfError"
        }
    }

    Write-Host "`n--- Terraform Outputs ---" -ForegroundColor Yellow
    terraform output -json
    Pop-Location

    Write-Host "`nInfra $Action complete.`n" -ForegroundColor Green
}
catch {
    if (Test-Path $TerraformDir) { Pop-Location -ErrorAction SilentlyContinue }
    $errorContext = @{
        error      = $_.Exception.Message
        scriptLine = $_.InvocationInfo.ScriptLineNumber
        script     = "infra.ps1"
    }
    $contextPath = Join-Path $env:BUILD_ARTIFACTSTAGINGDIRECTORY "error-context.json"
    $errorContext | ConvertTo-Json | Set-Content $contextPath -Force
    Write-Host "Error context saved to $contextPath" -ForegroundColor Red
    throw
}