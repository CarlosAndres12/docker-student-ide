#!/usr/bin/env pwsh
# ---------------------------------------------------------------------------
# docker-student-ide -- One-liner install (Windows PowerShell)
#
# Usage:
#   irm https://raw.githubusercontent.com/CarlosAndres12/docker-student-ide/main/scripts/install.ps1 | iex
#
#   # With arguments forwarded to start.ps1:
#   irm <url> | iex
#   # (start.ps1 handles -d, --build, etc. after install completes)
# ---------------------------------------------------------------------------
param()

$repoUrl = "https://github.com/CarlosAndres12/docker-student-ide.git"
$repoDir = "docker-student-ide"

# -- Check for git -----------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Error: git is required. Install it first."
    Write-Host "  https://git-scm.com/download/win"
    Write-Host "  or: winget install Git.Git"
    exit 1
}

# -- Already in repo? ---------------------------------------------------------
if ((Test-Path "start.ps1") -and (Test-Path "docker-compose.yml")) {
    Write-Host "[*] Already in docker-student-ide. Running start.ps1..."
    & ".\start.ps1" @args
    exit $LASTEXITCODE
}

# -- Clone --------------------------------------------------------------------
Write-Host "[*] Cloning docker-student-ide..."
if (Test-Path $repoDir) {
    Write-Host "[*] Directory $repoDir already exists. Using existing clone."
} else {
    $null = git clone $repoUrl $repoDir 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Failed to clone repository. Check your internet connection."
        exit 1
    }
}

Set-Location $repoDir

# -- Run ----------------------------------------------------------------------
Write-Host "[*] Starting docker-student-ide..."
& ".\start.ps1" @args
exit $LASTEXITCODE
