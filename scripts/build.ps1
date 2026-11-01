# =============================================================================
# build.ps1 — Docker build + Trivy scan + ACR push
# Called by: azure-pipelines.yml → Build stage
# Auth: AzureCLI@2 (OIDC) — az acr login uses the pipeline identity
#
# Reads Terraform outputs to get ACR details.
# Scans BEFORE push — dirty images never reach the registry.
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

$acrName       = (terraform output -raw acr_name)
$acrServer     = (terraform output -raw acr_login_server)
Pop-Location

$fullImage = "${acrServer}/${imageName}:${ImageTag}"
Write-Host "  ACR: $acrName ($acrServer)" -ForegroundColor Yellow
Write-Host "  Image: $fullImage" -ForegroundColor Yellow

# --- Docker Build ---
Write-Host "[3/6] Building Docker image..."
docker build -f $DockerfilePath -t $fullImage $BuildContext
if ($LASTEXITCODE -ne 0) { throw "Docker build failed" }
Write-Host "  -> Build OK" -ForegroundColor Green

# Show image size
$imageSize = docker image inspect $fullImage --format '{{.Size}}' | ForEach-Object { [math]::Round($_ / 1MB, 1) }
Write-Host "  -> Image size: ${imageSize} MB" -ForegroundColor Yellow

# --- Install Trivy ---
Write-Host "[4/6] Installing Trivy..."
$trivyVersion = "0.57.1"
curl -sLo /tmp/trivy.deb "https://github.com/aquasecurity/trivy/releases/download/v${trivyVersion}/trivy_${trivyVersion}_Linux-64bit.deb"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Direct download failed, trying apt..." -ForegroundColor Yellow
    sudo apt-get update -qq
    sudo apt-get install -y -qq wget apt-transport-https gnupg lsb-release
    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > $null
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/trivy.list
    sudo apt-get update -qq
    sudo apt-get install -y -qq trivy
} else {
    sudo dpkg -i /tmp/trivy.deb
    rm /tmp/trivy.deb
}
Write-Host "  -> $(trivy version | Select-Object -First 1)" -ForegroundColor Green

# --- Trivy Scan (BEFORE push — dirty images never reach ACR) ---
Write-Host "[5/6] Scanning for CVEs..."
trivy image --severity CRITICAL --exit-code 1 --no-progress $fullImage
if ($LASTEXITCODE -ne 0) {
    Write-Host "  -> CRITICAL CVEs found. Image NOT pushed." -ForegroundColor Red
    throw "Trivy scan failed: CRITICAL vulnerabilities detected"
}
Write-Host "  -> Zero CRITICAL CVEs" -ForegroundColor Green

# Generate SBOM
Write-Host "  Generating SBOM..."
trivy image --format spdx-json --output sbom.json $fullImage 2>$null
Write-Host "  -> SBOM saved: sbom.json" -ForegroundColor Green

# --- ACR Login + Push (same step — token expires across steps) ---
Write-Host "[6/6] Pushing to ACR..."
az acr login --name $acrName
if ($LASTEXITCODE -ne 0) { throw "ACR login failed" }

docker push $fullImage
if ($LASTEXITCODE -ne 0) { throw "Docker push failed" }
Write-Host "  -> Pushed: $fullImage" -ForegroundColor Green

Write-Host "`nBuild complete.`n" -ForegroundColor Green