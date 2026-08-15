#!/usr/bin/env pwsh
# ---------------------------------------------------------------------------
# docker-student-ide -- Native Windows one-liner install
#
# Usage:
#   irm https://raw.githubusercontent.com/CarlosAndres12/docker-student-ide/main/scripts/install-native.ps1 | iex
#
# Run it from the folder where you want the workspace to live. It downloads
# the repository as a ZIP (no Git required), extracts it, and runs
# setup-windows.ps1 in a child PowerShell with execution-policy bypass.
#
# The `irm | iex` form runs in-memory, so it works even under a Restricted
# execution policy and on machines without Git.
# ---------------------------------------------------------------------------
param()

# -- Helper: pause before exit (prevents terminal from closing on error) ----------
function Test-IsNonInteractive {
    return $env:DOCKER_STUDENT_IDE_NONINTERACTIVE -eq "1"
}

function Exit-WithPause {
    param([int]$Code = 0)
    if ($Code -ne 0) {
        Write-Host ""
        Write-Host "[!]  Ocurrio un error (codigo $Code). Revisa el mensaje arriba."
        Write-Host "   An error occurred (code $Code). Check the message above."
    }
    Write-Host ""
    if (-not (Test-IsNonInteractive)) {
        Read-Host "Presiona Enter para salir / Press Enter to exit"
    }
    exit $Code
}

# -- Helper: refresh PATH from the Windows registry --------------------------
function Reset-PathFromRegistry {
    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        $env:Path = @([Environment]::GetEnvironmentVariable('Path','Machine'), [Environment]::GetEnvironmentVariable('Path','User')) -join ';'
    }
}

$zipUrl = "https://github.com/CarlosAndres12/docker-student-ide/archive/refs/heads/main.zip"
$repoDir = "docker-student-ide"

function Invoke-ChildPowerShell {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,
        [string[]]$ArgsList = @()
    )

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @ArgsList 2>&1
    $LASTEXITCODE
}

function Invoke-NativeInstaller {
    param([string[]]$ArgsList = @())

# -- TLS 1.2 (PowerShell 5.1 on older Windows 10 needs this for GitHub) ------
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}

Reset-PathFromRegistry

# -- Helper: run setup-windows.ps1 in a child PowerShell with bypass ---------
# Bypass is child-scoped, so a Restricted policy cannot block the nested call.
function Invoke-SetupScript {
    param([string[]]$ArgsList)
    $out = Invoke-ChildPowerShell -ScriptPath (Join-Path $PWD 'setup-windows.ps1') -ArgsList $ArgsList
    if ($out -is [array]) {
        $childExitCode = $out[-1]
        $childOutput = $out[0..($out.Count - 2)]
    } else {
        $childExitCode = $out
        $childOutput = @()
    }
    if ($childExitCode -ne 0 -and ($childOutput -match 'UnauthorizedAccess|running scripts is disabled|not digitally signed')) {
        Write-Host "  [!] Politica de ejecucion bloqueada. Corre: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
        Write-Host "     Execution policy blocked the script. Run: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
        Exit-WithPause -Code 1   # bilingual hint + pause; child never ran
    }
    return $childExitCode
}

# -- Already in repo? ---------------------------------------------------------
if ((Test-Path "setup-windows.ps1") -and (Test-Path "requirements-windows.txt")) {
    Write-Host "[*] Ya en docker-student-ide. Ejecutando setup-windows.ps1..."
    return (Invoke-SetupScript -ArgsList $ArgsList)
}

# -- Download the repository as a ZIP (no Git required) ----------------------
Write-Host "[*] Descargando docker-student-ide..."
$targetDir = Join-Path $PWD $repoDir
if (-not (Test-Path (Join-Path $targetDir "setup-windows.ps1"))) {
    $zipPath = Join-Path ([System.IO.Path]::GetTempPath()) "docker-student-ide-main.zip"
    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    } catch {
        Write-Host "Error: No se pudo descargar el repositorio. Revisa tu conexion a internet."
        Write-Host "       Could not download the repository. Check your internet connection."
        Exit-WithPause -Code 1
    }

    $extractDir = Join-Path ([System.IO.Path]::GetTempPath()) "docker-student-ide-extract"
    if (Test-Path $extractDir) {
        Remove-Item $extractDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
    try {
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    } catch {
        Write-Host "Error: No se pudo extraer el repositorio descargado."
        Write-Host "       Could not extract the downloaded repository."
        Exit-WithPause -Code 1
    }
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

    # GitHub archives extract into a single top-level folder.
    $extracted = Get-ChildItem -Path $extractDir -Directory | Select-Object -First 1
    if (-not $extracted) {
        Write-Host "Error: El archivo descargado no contiene el repositorio esperado."
        Write-Host "       The downloaded archive does not contain the expected repository."
        Exit-WithPause -Code 1
    }
    Move-Item -Path $extracted.FullName -Destination $targetDir
    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
}

Set-Location $targetDir

# -- Run ----------------------------------------------------------------------
Write-Host "[*] Iniciando la instalacion nativa (esto puede tardar)..."
return (Invoke-SetupScript -ArgsList $ArgsList)
}

if ($MyInvocation.InvocationName -ne '.') {
    exit (Invoke-NativeInstaller -ArgsList $args)
}
