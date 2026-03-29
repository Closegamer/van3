# Publishes minimal worker bundle to ../van3_client (sibling of repo root). Does not overwrite .env or *.exe there.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$parent = Split-Path -Parent $repoRoot
$clientDir = Join-Path $parent "van3_client"
$pkg = Join-Path $repoRoot "packaging\van3_client"

foreach ($rel in @("run_van.ps1", "run_van.bat")) {
    $src = Join-Path $repoRoot $rel
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Error "Missing: $src"
    }
}
if (-not (Test-Path -LiteralPath $pkg)) {
    Write-Error "Missing packaging folder: $pkg"
}

New-Item -ItemType Directory -Force -Path $clientDir | Out-Null

Copy-Item (Join-Path $repoRoot "run_van.ps1") (Join-Path $clientDir "run_van.ps1") -Force
Copy-Item (Join-Path $repoRoot "run_van.bat") (Join-Path $clientDir "run_van.bat") -Force
Copy-Item (Join-Path $pkg ".env.example") (Join-Path $clientDir ".env.example") -Force
Copy-Item (Join-Path $pkg "README.md") (Join-Path $clientDir "README.md") -Force

Write-Host "OK: $clientDir" -ForegroundColor Green
Write-Host "Add VanSearch.exe and .env (from .env.example) in that folder if needed."
