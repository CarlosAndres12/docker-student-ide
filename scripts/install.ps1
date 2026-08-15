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
# Registry-backed PATH refresh is Windows-only. On other platforms there is
# no registry to read, and building $env:Path from empty entries corrupts
# command resolution and native exit codes inside the caller's scope.
function Reset-PathFromRegistry {
    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        $env:Path = @([Environment]::GetEnvironmentVariable('Path','Machine'), [Environment]::GetEnvironmentVariable('Path','User')) -join ';'
    }
}

$repoUrl = "https://github.com/CarlosAndres12/docker-student-ide.git"
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

function Invoke-Installer {
    param([string[]]$ArgsList = @())

# -- Refresh PATH from registry (Machine + User) ------------------------------
# Picks up git / Docker installed this session without restarting the terminal.
Reset-PathFromRegistry

# -- Check for git -----------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "[!] Git no esta instalado. Instalandolo con winget..."
    Write-Host "   Git is not installed. Installing it with winget..."
    $wingetOutput = winget install -e --id Git.Git --accept-source-agreements --accept-package-agreements 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "[!] No se pudo instalar Git automaticamente. Instalalo manualmente:"
        Write-Host "   Could not install Git automatically. Install it manually:"
        Write-Host "     https://git-scm.com/download/win"
        Write-Host "   Luego ejecuta este script de nuevo."
        Write-Host "   Then run this script again."
        Exit-WithPause -Code 1
    }
    # Git.Git sets the Machine PATH -- refresh the session so cloning can proceed.
    Reset-PathFromRegistry
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host ""
        Write-Host "[!] Git se instalo pero no se detecta en el PATH. Reinicia la terminal o instalalo manualmente:"
        Write-Host "   Git installed but is not detected on PATH. Restart the terminal or install it manually:"
        Write-Host "     https://git-scm.com/download/win"
        Exit-WithPause -Code 1
    }
}

# -- Helper: run start.ps1 in a child powershell with ExecutionPolicy Bypass ---
# Bypass is child-scoped, so a Restricted policy cannot block the nested call;
# args are forwarded positionally after -File and the child's exit code is
# propagated. Write-Host output streams straight to the console; native errors
# are captured here so a blocked policy can be detected and explained.
function Invoke-StartScript {
    param([string[]]$ArgsList)
    $out = Invoke-ChildPowerShell -ScriptPath (Join-Path $PWD 'start.ps1') -ArgsList $ArgsList
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
if ((Test-Path "start.ps1") -and (Test-Path "docker-compose.yml")) {
    Write-Host "[*] Already in docker-student-ide. Running start.ps1..."
    return (Invoke-StartScript -ArgsList $ArgsList)
}

# -- Clone --------------------------------------------------------------------
Write-Host "[*] Cloning docker-student-ide..."
if (Test-Path $repoDir) {
    Write-Host "[*] Directory $repoDir already exists. Using existing clone."
} else {
    $cloneOutput = git clone $repoUrl $repoDir 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Failed to clone repository. Check your internet connection."
        Exit-WithPause -Code 1
    }
}

Set-Location $repoDir

# -- Run ----------------------------------------------------------------------
Write-Host "[*] Starting docker-student-ide..."
$exitCode = Invoke-StartScript -ArgsList $ArgsList
return $exitCode
}

if ($MyInvocation.InvocationName -ne '.') {
    exit (Invoke-Installer -ArgsList $args)
}
