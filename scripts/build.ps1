# =============================================================================
# build.ps1 — Docker build + Trivy scan + ACR push
# =============================================================================
param(
    [Parameter(Mandatory)][string]$TerraformDir,
    [Parameter(Mandatory)][string]$BackendRG,
    [Parameter(Mandatory)][string]$BackendSA,
    [Parameter(Mandatory)][string]$BackendContainer,
    [Parameter(Mandatory)][string]$BackendKey,
    [Parameter(Mandatory)][string]$DockerfilePath,
    [Parameter(Mandatory)][string]$BuildContext,
    [Parameter(Mandatory)][string]$ImageTag
)

$ErrorActionPreference = "Stop"

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " BUILD: Docker + Trivy + ACR Push" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    $imageName = "atlas-platform-app"

    # --- Install Terraform (to read outputs from state) ---
    Write-Host "[1/6] Installing Terraform..."
    $tfVersion = "1.9.8"
    curl -sLo /tmp/tf.zip "https://releases.hashicorp.com/terraform/$tfVersion/terraform_${tfVersion}_linux_amd64.zip"
    sudo unzip -o /tmp/tf.zip -d /usr/local/bin | Out-Null
    rm /tmp/tf.zip

    # --- Read Terraform outputs ---
    Write-Host "[2/6] Reading Terraform outputs..."
    $env:ARM_USE_OIDC        = "true"
    $env:ARM_CLIENT_ID       = $env:servicePrincipalId
    $env:ARM_OIDC_TOKEN      = $env:idToken
    $env:ARM_TENANT_ID       = $env:tenantId
    $env:ARM_SUBSCRIPTION_ID = (az account show --query id -o tsv)

    Push-Location $TerraformDir
    terraform init -backend-config="resource_group_name=$BackendRG" `
        -backend-config="storage_account_name=$BackendSA" `
        -backend-config="container_name=$BackendContainer" `
        -backend-config="key=$BackendKey" -input=false | Out-Null

    $acrName   = (terraform output -raw acr_name)
    $acrServer = (terraform output -raw acr_login_server)
    Pop-Location

    $fullImage = "${acrServer}/${imageName}:${ImageTag}"
    Write-Host "  ACR: $acrName ($acrServer)" -ForegroundColor Yellow
    Write-Host "  Image: $fullImage" -ForegroundColor Yellow

    # --- Docker Build ---
    Write-Host "[3/6] Building Docker image..."
    docker build -f $DockerfilePath -t $fullImage $BuildContext
    if ($LASTEXITCODE -ne 0) { throw "Docker build failed" }
    Write-Host "  -> Build OK" -ForegroundColor Green

    $imageSize = docker image inspect $fullImage --format '{{.Size}}' | ForEach-Object { [math]::Round($_ / 1MB, 1) }
    Write-Host "  -> Image size: ${imageSize} MB" -ForegroundColor Yellow

    # --- Install Trivy ---
    Write-Host "[4/6] Installing Trivy..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq wget apt-transport-https gnupg lsb-release
    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/trivy.list
    sudo apt-get update -qq
    sudo apt-get install -y -qq trivy
    if ($LASTEXITCODE -ne 0) { throw "Trivy installation failed" }
    Write-Host "  -> $(trivy version | Select-Object -First 1)" -ForegroundColor Green

    # --- Trivy Scan ---
    Write-Host "[5/6] Scanning for CVEs..."
    trivy image --severity CRITICAL --exit-code 1 --no-progress $fullImage
    if ($LASTEXITCODE -ne 0) {
        throw "Trivy scan failed: CRITICAL vulnerabilities detected. Image NOT pushed."
    }
    Write-Host "  -> Zero CRITICAL CVEs" -ForegroundColor Green

    Write-Host "  Generating SBOM..."
    trivy image --format spdx-json --output sbom.json $fullImage 2>$null
    Write-Host "  -> SBOM saved" -ForegroundColor Green

    # --- ACR Login + Push ---
    Write-Host "[6/6] Pushing to ACR..."
    az acr login --name $acrName
    if ($LASTEXITCODE -ne 0) { throw "ACR login failed" }

    docker push $fullImage
    if ($LASTEXITCODE -ne 0) { throw "Docker push failed" }
    Write-Host "  -> Pushed: $fullImage" -ForegroundColor Green

    Write-Host "`nBuild complete.`n" -ForegroundColor Green
}
catch {
    Pop-Location -ErrorAction SilentlyContinue
    $errorContext = @{
        error      = $_.Exception.Message
        scriptLine = $_.InvocationInfo.ScriptLineNumber
        script     = "build.ps1"
    }
    $contextPath = Join-Path $env:BUILD_ARTIFACTSTAGINGDIRECTORY "error-context.json"
    $errorContext | ConvertTo-Json | Set-Content $contextPath -Force
    Write-Host "Error context saved to $contextPath" -ForegroundColor Red
    throw
}