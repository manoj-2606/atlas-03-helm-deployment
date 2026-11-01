# =============================================================================
# deploy.ps1 — Helm deploy + rollout wait + smoke test
# =============================================================================
param(
    [Parameter(Mandatory)][string]$TerraformDir,
    [Parameter(Mandatory)][string]$BackendRG,
    [Parameter(Mandatory)][string]$BackendSA,
    [Parameter(Mandatory)][string]$BackendContainer,
    [Parameter(Mandatory)][string]$BackendKey,
    [Parameter(Mandatory)][string]$ChartPath,
    [Parameter(Mandatory)][string]$ValuesFile,
    [Parameter(Mandatory)][string]$ReleaseName,
    [Parameter(Mandatory)][string]$Namespace,
    [Parameter(Mandatory)][string]$ImageTag
)

$ErrorActionPreference = "Stop"

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " DEPLOY: Helm + Smoke Test" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    # --- Install Terraform ---
    Write-Host "[1/7] Installing Terraform..."
    $tfVersion = "1.9.8"
    curl -sLo /tmp/tf.zip "https://releases.hashicorp.com/terraform/$tfVersion/terraform_${tfVersion}_linux_amd64.zip"
    sudo unzip -o /tmp/tf.zip -d /usr/local/bin | Out-Null
    rm /tmp/tf.zip

    # --- Read Terraform outputs ---
    Write-Host "[2/7] Reading Terraform outputs..."
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

    $resourceGroup = (terraform output -raw resource_group_name)
    $aksCluster    = (terraform output -raw aks_cluster_name)
    $acrServer     = (terraform output -raw acr_login_server)
    Pop-Location

    Write-Host "  RG: $resourceGroup | AKS: $aksCluster" -ForegroundColor Yellow

    # --- Install kubectl + Helm ---
    Write-Host "[3/7] Installing kubectl + Helm..."
    az aks install-cli 2>$null
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    Write-Host "  -> kubectl: $(kubectl version --client --short 2>$null)" -ForegroundColor Green
    Write-Host "  -> helm: $(helm version --short 2>$null)" -ForegroundColor Green

    # --- Get AKS credentials ---
    Write-Host "[4/7] Getting AKS credentials..."
    az aks get-credentials --resource-group $resourceGroup --name $aksCluster --overwrite-existing
    if ($LASTEXITCODE -ne 0) { throw "Failed to get AKS credentials" }

    $nodeCount = kubectl get nodes --no-headers 2>$null | Measure-Object | Select-Object -ExpandProperty Count
    Write-Host "  -> Connected. Nodes: $nodeCount" -ForegroundColor Green

    # --- Create namespace ---
    Write-Host "[5/7] Creating namespace: $Namespace"
    kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f -
    Write-Host "  -> OK" -ForegroundColor Green

    # --- Helm deploy ---
    Write-Host "[6/7] Deploying via Helm..."
    $imageRepo = "${acrServer}/atlas-platform-app"

    Write-Host "  Release: $ReleaseName"
    Write-Host "  Chart: $ChartPath"
    Write-Host "  Image: ${imageRepo}:${ImageTag}"

    helm upgrade --install $ReleaseName $ChartPath `
        -f $ValuesFile `
        --namespace $Namespace `
        --set image.repository=$imageRepo `
        --set image.tag=$ImageTag `
        --wait `
        --timeout 5m0s

    if ($LASTEXITCODE -ne 0) { throw "Helm deploy failed" }
    Write-Host "  -> Release deployed" -ForegroundColor Green

    helm list -n $Namespace

    Write-Host "`n  Pod status:"
    kubectl get pods -n $Namespace -l app.kubernetes.io/instance=$ReleaseName -o wide

    # --- Smoke Test ---
    Write-Host "`n[7/7] Smoke test: /health"
    $serviceUrl = "http://${ReleaseName}.${Namespace}.svc.cluster.local/health"

    $smokeResult = kubectl run smoke-test `
        --rm -i --restart=Never `
        --namespace $Namespace `
        --image=curlimages/curl `
        --timeout=60s `
        -- curl -sf --max-time 10 $serviceUrl 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  -> PASSED" -ForegroundColor Green
        Write-Host "  Response: $smokeResult"
    } else {
        Write-Host "  -> FAILED" -ForegroundColor Red
        Write-Host "  Response: $smokeResult"
        Write-Host "`n  --- Debug Info ---" -ForegroundColor Yellow
        kubectl get endpoints $ReleaseName -n $Namespace
        $podName = kubectl get pods -n $Namespace -l app.kubernetes.io/instance=$ReleaseName -o jsonpath='{.items[0].metadata.name}' 2>$null
        if ($podName) {
            Write-Host "  Pod logs (last 20):"
            kubectl logs $podName -n $Namespace --tail=20
        }
        throw "Smoke test failed"
    }

    Write-Host "`nDeploy complete.`n" -ForegroundColor Green
}
catch {
    Pop-Location -ErrorAction SilentlyContinue
    $errorContext = @{
        error      = $_.Exception.Message
        scriptLine = $_.InvocationInfo.ScriptLineNumber
        script     = "deploy.ps1"
    }
    $contextPath = Join-Path $env:BUILD_ARTIFACTSTAGINGDIRECTORY "error-context.json"
    $errorContext | ConvertTo-Json | Set-Content $contextPath -Force
    Write-Host "Error context saved to $contextPath" -ForegroundColor Red
    throw
}