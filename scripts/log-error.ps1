# =============================================================================
# log-error.ps1 — Automated error logger
# Called by: pipeline with condition: failed()
# Reads error-context.json (written by failed .ps1 script) → updates logs.json → git push
#
# The script auto-captures: run number, stage, error message, timestamp.
# You manually fill in: cause, fix, prevention (after debugging).
# =============================================================================
param(
    [Parameter(Mandatory)][string]$Stage,
    [Parameter(Mandatory)][string]$BuildNumber,
    [Parameter(Mandatory)][string]$RepoDir
)

$ErrorActionPreference = "Continue"  # Don't fail the pipeline further if logging fails
Write-Host "`n========================================" -ForegroundColor Red
Write-Host " ERROR LOGGER: Capturing failure" -ForegroundColor Red
Write-Host "========================================`n" -ForegroundColor Red

# --- Read error context (written by the failed script) ---
$errorContextPath = Join-Path $env:BUILD_ARTIFACTSTAGINGDIRECTORY "error-context.json"
$logsJsonPath     = Join-Path $RepoDir "logs.json"

if (Test-Path $errorContextPath) {
    $errorContext = Get-Content $errorContextPath -Raw | ConvertFrom-Json
    $errorMessage = $errorContext.error
    $scriptLine   = $errorContext.scriptLine
    Write-Host "Error captured from script: $errorMessage" -ForegroundColor Yellow
} else {
    $errorMessage = "Error context not found — check pipeline logs manually"
    $scriptLine   = "unknown"
    Write-Host "No error-context.json found. Using fallback." -ForegroundColor Yellow
}

# --- Read existing logs.json ---
if (-not (Test-Path $logsJsonPath)) {
    Write-Host "logs.json not found at $logsJsonPath — skipping" -ForegroundColor Yellow
    return
}

$logs = Get-Content $logsJsonPath -Raw | ConvertFrom-Json

# --- Build new error entry ---
$newError = [PSCustomObject]@{
    run        = "#$BuildNumber"
    stage      = $Stage
    error      = $errorMessage
    scriptLine = $scriptLine
    timestamp  = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    cause      = "TODO"
    fix        = "TODO"
    prevention = "TODO"
}

# Append to errors array
$errorsList = [System.Collections.ArrayList]@($logs.errors)
$errorsList.Add($newError) | Out-Null
$logs.errors = $errorsList.ToArray()

# --- Write updated logs.json ---
$logs | ConvertTo-Json -Depth 10 | Set-Content $logsJsonPath -Force
Write-Host "Updated logs.json with error entry" -ForegroundColor Green

# --- Git commit + push to ADO ---
Write-Host "`nPushing logs.json to repo..."
Push-Location $RepoDir

git config user.email "pipeline@atlas-platform.dev"
git config user.name "Atlas Pipeline"

git add logs.json
git commit -m "auto-log: $Stage failed in build #$BuildNumber"

if ($LASTEXITCODE -eq 0) {
    git push origin HEAD:main
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  -> Pushed to ADO repo" -ForegroundColor Green
    } else {
        Write-Host "  -> Push failed (check Build Service permissions)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  -> Nothing to commit (logs.json unchanged)" -ForegroundColor Yellow
}

Pop-Location
Write-Host "`nError logged. Fill in cause/fix/prevention after debugging.`n" -ForegroundColor Red