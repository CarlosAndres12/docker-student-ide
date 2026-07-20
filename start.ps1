<#
.SYNOPSIS
    docker-student-ide Bootstrap Script for Windows (PowerShell)
.DESCRIPTION
    This script:
      1. Checks if Docker Desktop is installed.  If missing, installs it:
           - via winget (Windows Package Manager, primary)
           - via choco  (Chocolatey, fallback)
           - or provides a direct download link
      2. Waits for the Docker daemon to start (polls `docker info` up to 120s).
      3. Checks that `docker compose` (v2) is available.
      4. Sets PUID=1000 / PGID=1000 in .env (idempotent).
      5. Runs `docker compose up` with any passed arguments.
.NOTES
    Run this in PowerShell as Administrator for best results.
    If winget/choco are unavailable, Docker Desktop must be installed manually.
#>

$ErrorActionPreference = "Stop"

# ── Helper: bilingual message ────────────────────────────────────────────────
function Write-Message {
    param([string]$Spanish, [string]$English)
    Write-Host "🔧 $Spanish"
    Write-Host "   $English"
}

# ── Section 1: Check / Install Docker Desktop ────────────────────────────────
$dockerPath = (Get-Command "docker" -ErrorAction SilentlyContinue).Source
if ($dockerPath) {
    Write-Message "Docker ya está instalado / Docker is already installed." "Found at: $dockerPath"
} else {
    Write-Message "Docker no encontrado. Instalando..." "Docker not found. Installing..."

    # Attempt 1: winget
    $wingetPath = (Get-Command "winget" -ErrorAction SilentlyContinue).Source
    if ($wingetPath) {
        Write-Message "Instalando Docker Desktop via winget..." "Installing Docker Desktop via winget..."
        try {
            & winget install -e --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements
            Write-Message "Instalación completada. Iniciando Docker Desktop..." "Install complete. Launching Docker Desktop..."
            # Start Docker Desktop (installed for current user)
            $dockerDesktop = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
            if (Test-Path $dockerDesktop) {
                Start-Process -FilePath $dockerDesktop
            } else {
                # Try alternative path
                $ddAlt = "$env:LOCALAPPDATA\Docker\Docker Desktop\Docker Desktop.exe"
                if (Test-Path $ddAlt) {
                    Start-Process -FilePath $ddAlt
                } else {
                    Write-Message "Busca 'Docker Desktop' en el menú Inicio y ábrelo." "Search for 'Docker Desktop' in the Start Menu and launch it."
                }
            }
        } catch {
            Write-Message "Error instalando con winget. Intentando con Chocolatey..." "winget install failed. Trying Chocolatey..."
            $wingetFailed = $true
        }
    } else {
        $wingetFailed = $true
    }

    # Attempt 2: choco (fallback)
    if ($wingetFailed) {
        $chocoPath = (Get-Command "choco" -ErrorAction SilentlyContinue).Source
        if ($chocoPath) {
            Write-Message "Instalando Docker Desktop via Chocolatey..." "Installing Docker Desktop via Chocolatey..."
            try {
                & choco install docker-desktop -y
                Write-Message "Instalación completada. Busca 'Docker Desktop' en el menú Inicio y ábrelo." "Install complete. Search for 'Docker Desktop' in Start Menu and launch it."
            } catch {
                Write-Message "Error instalando con Chocolatey." "Chocolatey install also failed."
                $allFailed = $true
            }
        } else {
            $allFailed = $true
        }
    }

    if ($allFailed) {
        Write-Message "No se pudo instalar Docker automáticamente." "Could not auto-install Docker."
        Write-Host ""
        Write-Host "   📥 Descárgalo manualmente desde / Download manually from:"
        Write-Host "      https://docs.docker.com/desktop/install/windows-install/"
        Write-Host ""
        Write-Host "   Luego ejecuta este script de nuevo / Then run this script again."
        exit 1
    }

    Write-Host ""
    Write-Host "⚠️  Una vez que Docker Desktop esté abierto y corriendo, ejecuta este script de nuevo."
    Write-Host "   Once Docker Desktop is open and running, run this script again."
    Write-Host "   (O simplemente continúa — el script esperará hasta 2 minutos a que Docker arranque.)"
    Write-Host "   (Or just continue — the script will wait up to 2 minutes for Docker to start.)"
    Write-Host ""
}

# ── Section 2: Wait for Docker daemon (poll docker info) ─────────────────────
Write-Message "Esperando a que el servicio Docker esté listo..." "Waiting for the Docker daemon to be ready..."
$maxRetries = 24   # 24 * 5 = 120 seconds
$retryCount = 0
$dockerReady = $false

while ($retryCount -lt $maxRetries) {
    $result = docker info 2>&1
    if ($LASTEXITCODE -eq 0) {
        $dockerReady = $true
        break
    }
    $retryCount++
    if ($retryCount -eq 1) {
        Write-Host "   ⏳ Docker aún no responde. Esperando... (hasta 2 minutos)"
        Write-Host "      Docker not responding yet. Waiting... (up to 2 minutes)"
    }
    Start-Sleep -Seconds 5
}

if (-not $dockerReady) {
    Write-Message "Docker no arrancó después de 2 minutos." "Docker did not start after 2 minutes."
    Write-Host ""
    Write-Host "   💡 Asegúrate de que Docker Desktop esté abierto (menú Inicio → Docker Desktop)."
    Write-Host "      Make sure Docker Desktop is open (Start Menu → Docker Desktop)."
    Write-Host "   💡 Revisa el ícono en la bandeja del sistema — debe decir 'Docker Desktop is running'."
    Write-Host "      Check the system tray icon — it should say 'Docker Desktop is running'."
    Write-Host "   💡 Luego ejecuta este script de nuevo."
    Write-Host "      Then run this script again."
    exit 1
}

Write-Message "✅ Docker está funcionando." "Docker is running."

# ── Section 3: Check docker compose (v2) ─────────────────────────────────────
$composeResult = docker compose version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Message "docker compose (v2) no disponible. ¿Versión antigua de Docker Desktop?" "docker compose (v2) not available. Outdated Docker Desktop?"
    Write-Host "   Actualiza Docker Desktop desde https://docs.docker.com/desktop/install/windows-install/"
    Write-Host "   Update Docker Desktop from the link above."
    exit 1
}
Write-Message "✅ docker compose (v2) disponible." "docker compose (v2) available."

# ── Section 4: Set PUID / PGID in .env (Windows → 1000:1000) ────────────────
$envPath = Join-Path -Path $PWD -ChildPath ".env"

# Helper: ensure a variable is set in .env
function Update-EnvVar {
    param([string]$VarName, [string]$Value, [string]$FilePath)
    $pattern = "^${VarName}=.*"
    $line = "${VarName}=${Value}"

    if (Test-Path $FilePath) {
        $content = Get-Content -Path $FilePath -Raw
        if ($content -match "(?m)^${VarName}=.*") {
            $content = $content -replace "(?m)^${VarName}=.*", $line
            Set-Content -Path $FilePath -Value $content -NoNewline
        } else {
            Add-Content -Path $FilePath -Value $line
        }
    } else {
        # Create .env from .env.example if it exists
        $examplePath = Join-Path -Path $PWD -ChildPath ".env.example"
        if (Test-Path $examplePath) {
            Copy-Item -Path $examplePath -Destination $FilePath
            # Now replace the value
            $content = Get-Content -Path $FilePath -Raw
            if ($content -match "(?m)^${VarName}=.*") {
                $content = $content -replace "(?m)^${VarName}=.*", $line
                Set-Content -Path $FilePath -Value $content -NoNewline
            } else {
                Add-Content -Path $FilePath -Value $line
            }
        } else {
            # Create minimal .env
            Set-Content -Path $FilePath -Value "${VarName}=${Value}"
        }
    }
}

# On Windows, Unix UIDs don't apply; WSL2 backend handles ownership.
# We set PUID=1000 PGID=1000 as safe defaults (same as Docker Desktop's WSL2 default).
Update-EnvVar -VarName "PUID" -Value "1000" -FilePath $envPath
Update-EnvVar -VarName "PGID" -Value "1000" -FilePath $envPath

Write-Message "📝 .env configurado con PUID=1000 PGID=1000." ".env configured with PUID=1000 PGID=1000."

# ── Section 5: Run docker compose up ─────────────────────────────────────────
Write-Message "🚀 Iniciando docker-student-ide..." "Starting docker-student-ide..."
Write-Host ""

# Pass through any arguments
if ($args.Count -gt 0) {
    & docker compose up @args
} else {
    & docker compose up
}

exit $LASTEXITCODE
