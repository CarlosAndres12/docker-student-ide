<#
.SYNOPSIS
    docker-student-ide Native Setup Script for Windows (PowerShell)
.DESCRIPTION
    Preferred Windows path: provisions the full docker-student-ide environment
    NATIVELY on Windows, without Docker. Equivalent to the Docker container but
    running directly on the host:

      0. Gate: winget availability + elevation guidance.
      1. Git (winget Git.Git).
      2. Node.js LTS (winget OpenJS.NodeJS.LTS).
      3. Python (winget, latest) + a repo-local virtual environment with the
         pinned ML/DL stack (torch CPU wheels + requirements-windows.txt).
      4. Global npm CLI tools (create-vite, typescript, npm-check-updates).
      5. AI agents: Pi (+ gentle-pi / gentle-engram / pi-free), OpenCode,
         Freebuff, engram (Go MCP server), gentle-ai (Go configurator), Qoder,
         and the Antigravity CLI (`agy`).
      6. Visual Studio Code (winget) + the harness extension set.
      7. Pi free-only routing (PI_FREE_ONLY=1 + ~/.pi/free.json).
      8. Launch VS Code on student_workspace/.
      9. Verification + version report.

    Everything is idempotent: already-installed tools are skipped. The core
    toolchain (Git, Node, Python, VS Code) fails hard on error; agent installs
    are best-effort and only warn.

    This script is Docker-free by design: it does not touch .env, PUID/PGID,
    the Compose file, or any container. start.ps1 remains the Docker path.

.NOTES
    Run in PowerShell. Administrator rights are recommended but not required
    (winget installs Git/Node/Python/VS Code per-user when not elevated).
#>

$ErrorActionPreference = "Continue"

# -- Helper: bilingual message ------------------------------------------------
function Write-Message {
    param([string]$Spanish, [string]$English)
    Write-Host "[*] $Spanish"
    Write-Host "   $English"
}

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

# -- Helper: is the process elevated? -----------------------------------------
function Test-IsAdmin {
    # Windows-only: the WindowsIdentity/WindowsPrincipal types are unavailable
    # on non-Windows .NET, so short-circuit there (keeps the script parseable
    # and testable under Linux pwsh without a Windows type dependency).
    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return $false
    }
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# -- Helper: install a winget package (idempotent by caller's presence check) --
function Invoke-WingetInstall {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$DisplayName
    )
    Write-Message "Instalando $DisplayName via winget..." "Installing $DisplayName via winget..."
    & winget install -e --id $Id --accept-source-agreements --accept-package-agreements
    return $LASTEXITCODE
}

# -- Helper: install an npm global only when the binary is missing ------------
function Install-NpmGlobal {
    param(
        [Parameter(Mandatory)][string]$Package,
        [Parameter(Mandatory)][string]$Binary
    )
    if (Get-Command $Binary -ErrorAction SilentlyContinue) {
        Write-Message "[OK] $Binary ya esta instalado." "$Binary already installed."
        return $true
    }
    Write-Message "Instalando $Package..." "Installing $Package..."
    & npm install -g $Package
    return ($LASTEXITCODE -eq 0)
}

# -- Helper: install the Antigravity CLI (Google `agy` binary) ----------------
function Install-AntigravityCli {
    if (Get-Command agy -ErrorAction SilentlyContinue) {
        Write-Message "[OK] Antigravity CLI (agy) ya esta instalado." "Antigravity CLI (agy) already installed."
        return $true
    }
    Write-Message "Instalando Antigravity CLI (agy)..." "Installing Antigravity CLI (agy)..."
    # The real Google Antigravity CLI is `agy`, installed from its official
    # script. The npm package `antigravity-cli` is a placeholder — do NOT use it.
    irm https://antigravity.google/cli/install.ps1 | iex
    Reset-PathFromRegistry
    if (Get-Command agy -ErrorAction SilentlyContinue) {
        return $true
    }
    Write-Host ""
    Write-Message "No se pudo detectar `agy` tras la instalacion." "Could not detect `agy` after install."
    Write-Host "   Reinstala manualmente: irm https://antigravity.google/cli/install.ps1 | iex"
    return $false
}

# -- Helper: install the Qoder CLI -------------------------------------------
function Install-QoderCli {
    if (Get-Command qodercli -ErrorAction SilentlyContinue) {
        Write-Message "[OK] Qoder (qodercli) ya esta instalado." "Qoder (qodercli) already installed."
        return $true
    }
    Write-Message "Instalando Qoder CLI..." "Installing Qoder CLI..."
    & curl.exe -fsSL https://qoder.com/install | bash
    if (Get-Command qodercli -ErrorAction SilentlyContinue) {
        return $true
    }
    Write-Host ""
    Write-Message "No se pudo detectar `qodercli` tras la instalacion." "Could not detect `qodercli` after install."
    return $false
}

# -- Helper: install a GitHub-released Go binary for Windows ------------------
# Downloads the `windows_amd64` zip, extracts the .exe, and installs it into a
# per-user bin directory that is added to the User PATH (persistent).
function Install-GoBinary {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Url
    )
    if (Get-Command $Name -ErrorAction SilentlyContinue) {
        Write-Message "[OK] $Name ya esta instalado." "$Name already installed."
        return $true
    }
    Write-Message "Instalando $Name v$Version..." "Installing $Name v$Version..."
    $binDir = Join-Path $env:LOCALAPPDATA "docker-student-ide\bin"
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    $zipPath = Join-Path $binDir "$Name-$Version.zip"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath $binDir -Force
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        $exe = Get-ChildItem -Path $binDir -Recurse -Filter "$Name.exe" | Select-Object -First 1
        if (-not $exe) {
            throw "$Name.exe not found in archive"
        }
        $target = Join-Path $binDir "$Name.exe"
        if ($exe.FullName -ne $target) {
            Copy-Item -Path $exe.FullName -Destination $target -Force
        }
        # Persist the bin dir on the User PATH so `$Name` resolves in new shells.
        $userPath = [Environment]::GetEnvironmentVariable('Path','User')
        if ($userPath -notlike "*$binDir*") {
            [Environment]::SetEnvironmentVariable('Path', "$userPath;$binDir", 'User')
        }
        Reset-PathFromRegistry
        return $true
    } catch {
        Write-Host ""
        Write-Message "Error instalando $Name." "Error installing $Name."
        Write-Host "   $($_.Exception.Message)"
        return $false
    }
}

# -- Helper: merge a hashtable into a JSON file (idempotent) ------------------
function Merge-JsonSettings {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Values
    )
    $settings = @{}
    if (Test-Path $Path) {
        try {
            $existing = Get-Content -Path $Path -Raw | ConvertFrom-Json -ErrorAction Stop
            $settings = @{}
            $existing.PSObject.Properties | ForEach-Object { $settings[$_.Name] = $_.Value }
        } catch {
            $settings = @{}
        }
    }
    foreach ($key in $Values.Keys) {
        $settings[$key] = $Values[$key]
    }
    $dir = Split-Path $Path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
}

function Invoke-Setup {
    param()

# -- Section 0: winget gate ---------------------------------------------------
Reset-PathFromRegistry

if (-not (Test-IsAdmin)) {
    Write-Message "Consejo: ejecuta como Administrador para mejores resultados." "Tip: run as Administrator for best results."
    Write-Host "   (Los paquetes de winget se instalan por usuario cuando no hay elevacion.)"
    Write-Host "   (winget packages install per-user when not elevated.)"
    Write-Host ""
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Message "winget no encontrado. Instala App Installer desde la Microsoft Store." "winget not found. Install App Installer from the Microsoft Store."
    Write-Host "   https://aka.ms/getwinget"
    Exit-WithPause -Code 1
}

# -- Section 1: Git -----------------------------------------------------------
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Message "[OK] Git ya esta instalado." "Git already installed."
} else {
    $code = Invoke-WingetInstall -Id "Git.Git" -DisplayName "Git"
    if ($code -ne 0) {
        Write-Message "No se pudo instalar Git automaticamente." "Could not auto-install Git."
        Write-Host "   https://git-scm.com/download/win"
        Exit-WithPause -Code 1
    }
    Reset-PathFromRegistry
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Message "Git instalado pero no se detecta en el PATH." "Git installed but not on PATH."
        Write-Host "   Reinicia la terminal y vuelve a ejecutar este script."
        Write-Host "   Restart the terminal and run this script again."
        Exit-WithPause -Code 1
    }
}

# -- Section 2: Node.js LTS ---------------------------------------------------
if (Get-Command node -ErrorAction SilentlyContinue) {
    Write-Message "[OK] Node.js ya esta instalado." "Node.js already installed."
} else {
    $code = Invoke-WingetInstall -Id "OpenJS.NodeJS.LTS" -DisplayName "Node.js LTS"
    if ($code -ne 0) {
        Write-Message "No se pudo instalar Node.js." "Could not auto-install Node.js."
        Write-Host "   https://nodejs.org/"
        Exit-WithPause -Code 1
    }
    Reset-PathFromRegistry
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Message "Node.js instalado pero no se detecta en el PATH." "Node.js installed but not on PATH."
        Write-Host "   Reinicia la terminal y vuelve a ejecutar este script."
        Write-Host "   Restart the terminal and run this script again."
        Exit-WithPause -Code 1
    }
}

# -- Section 3: Python (latest) + virtual environment -------------------------
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) {
    $code = Invoke-WingetInstall -Id "Python.Python.3.13" -DisplayName "Python"
    if ($code -ne 0) {
        Write-Message "No se pudo instalar Python." "Could not auto-install Python."
        Write-Host "   https://www.python.org/downloads/windows/"
        Exit-WithPause -Code 1
    }
    Reset-PathFromRegistry
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        # Fall back to the `py` launcher which winget installs alongside python.
        $pythonCmd = Get-Command py -ErrorAction SilentlyContinue
        if (-not $pythonCmd) {
            Write-Message "Python instalado pero no se detecta en el PATH." "Python installed but not on PATH."
            Write-Host "   Reinicia la terminal y vuelve a ejecutar este script."
            Write-Host "   Restart the terminal and run this script again."
            Exit-WithPause -Code 1
        }
    }
}

$venvPath = Join-Path $PWD ".venv"
$venvPython = Join-Path $venvPath "Scripts\python.exe"
if (Test-Path $venvPython) {
    Write-Message "[OK] Entorno virtual Python ya existe (.venv)." "Python virtual environment already exists (.venv)."
} else {
    Write-Message "Creando entorno virtual Python (.venv)..." "Creating Python virtual environment (.venv)..."
    if ($pythonCmd.Name -eq "py") {
        & $pythonCmd.Source -3.13 -m venv $venvPath
    } else {
        & $pythonCmd.Source -m venv $venvPath
    }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $venvPython)) {
        Write-Message "No se pudo crear el entorno virtual." "Could not create the virtual environment."
        Exit-WithPause -Code 1
    }
}

# Install the ML/DL stack into the venv. torch/torchvision come from the CPU
# wheel index first (mirrors the Dockerfile), then the rest resolves from
# requirements-windows.txt. Pinned versions target the latest Python (3.13).
Write-Message "Instalando stack Python (esto puede tardar)..." "Installing the Python stack (this may take a while)..."
& $venvPython -m pip install --upgrade pip
& $venvPython -m pip install --index-url https://download.pytorch.org/whl/cpu torch==2.6.0 torchvision==0.21.0
& $venvPython -m pip install -r (Join-Path $PWD "requirements-windows.txt")
if ($LASTEXITCODE -ne 0) {
    Write-Message "No se pudo instalar el stack Python." "Could not install the Python stack."
    Exit-WithPause -Code 1
}

# -- Section 4: global npm CLI tools (pinned) --------------------------------
$null = Install-NpmGlobal -Package "create-vite@5.1.0" -Binary "create-vite"
$null = Install-NpmGlobal -Package "typescript@5.6.2" -Binary "tsc"
$null = Install-NpmGlobal -Package "npm-check-updates@17.1.3" -Binary "ncu"

# -- Section 5: AI agents -----------------------------------------------------
Write-Message "Instalando asistentes de IA..." "Installing AI agents..."

# Pi (the default assistant). NOTE: `npm install -g pi` is a JOKE package that
# prints "3" — the real Pi CLI is @earendil-works/pi-coding-agent.
$null = Install-NpmGlobal -Package "@earendil-works/pi-coding-agent" -Binary "pi"
if (Get-Command pi -ErrorAction SilentlyContinue) {
    & pi install npm:gentle-pi
    & pi install npm:gentle-engram
    & npm exec --yes --package gentle-engram@latest -- pi-engram init
}

# OpenCode + Freebuff (npm globals)
$null = Install-NpmGlobal -Package "opencode-ai@latest" -Binary "opencode"
$null = Install-NpmGlobal -Package "freebuff@latest" -Binary "freebuff"

# pi-free (GitHub-sourced, pinned commit, stable install path)
$piFreePath = Join-Path $env:LOCALAPPDATA "pi-free"
if (-not (Test-Path $piFreePath)) {
    Write-Message "Instalando pi-free..." "Installing pi-free..."
    & git clone https://github.com/apmantza/pi-free.git $piFreePath
    Push-Location $piFreePath
    & git checkout 6119a187afa8f444376026836b60649cac3d3621
    Pop-Location
}
if (Get-Command pi -ErrorAction SilentlyContinue) {
    & pi install $piFreePath
}

# Engram MCP server (Go binary) + gentle-ai configurator (Go binary)
$null = Install-GoBinary -Name "engram" -Version "1.19.0" -Url "https://github.com/Gentleman-Programming/engram/releases/download/v1.19.0/engram_1.19.0_windows_amd64.zip"
$null = Install-GoBinary -Name "gentle-ai" -Version "2.1.10" -Url "https://github.com/Gentleman-Programming/gentle-ai/releases/download/v2.1.10/gentle-ai_2.1.10_windows_amd64.zip"
if (Get-Command gentle-ai -ErrorAction SilentlyContinue) {
    & gentle-ai install --agents opencode --scope=global
}

# Qoder + Antigravity CLI (best-effort)
$null = Install-QoderCli
$null = Install-AntigravityCli

# -- Section 6: VS Code + harness extensions ---------------------------------
if (Get-Command code -ErrorAction SilentlyContinue) {
    Write-Message "[OK] Visual Studio Code ya esta instalado." "Visual Studio Code already installed."
} else {
    $code = Invoke-WingetInstall -Id "Microsoft.VisualStudioCode" -DisplayName "Visual Studio Code"
    if ($code -ne 0) {
        Write-Message "No se pudo instalar Visual Studio Code." "Could not auto-install Visual Studio Code."
        Write-Host "   https://code.visualstudio.com/"
        Exit-WithPause -Code 1
    }
    Reset-PathFromRegistry
}

$extensions = @(
    "ms-toolsai.jupyter",
    "ms-toolsai.jupyter-renderers",
    "ms-toolsai.vscode-jupyter-cell-tags",
    "ms-python.python",
    "ms-python.vscode-pylance",
    "redhat.vscode-yaml",
    "humao.rest-client",
    "ms-azuretools.vscode-docker",
    "bradlc.vscode-tailwindcss",
    "christian-kohler.path-intellisense",
    "usernamehw.errorlens",
    "Gruntfuggly.todo-tree",
    "oderwat.indent-rainbow",
    "esbenp.prettier-vscode",
    "yzhang.markdown-all-in-one",
    "bierner.markdown-mermaid"
)

if (Get-Command code -ErrorAction SilentlyContinue) {
    Write-Message "Instalando extensiones de VS Code..." "Installing VS Code extensions..."
    $installed = @(& code --list-extensions)
    foreach ($ext in $extensions) {
        if ($installed -contains $ext) {
            Write-Host "   [OK] $ext ya instalado."
        } else {
            & code --install-extension $ext
        }
    }

    # User settings: forward Ctrl+key combos to agent TUIs in the terminal
    # (mirrors the code-server settings.json baked in the Docker image).
    $settingsPath = Join-Path $env:APPDATA "Code\User\settings.json"
    Merge-JsonSettings -Path $settingsPath -Values @{
        "terminal.integrated.sendKeybindingsToShell" = $true
        "terminal.integrated.allowChords" = $false
        "terminal.integrated.commandsToSkipShell" = @(
            "editor.action.clipboardCopyAction",
            "editor.action.clipboardPasteAction",
            "editor.action.clipboardCutAction",
            "workbench.action.terminal.focus",
            "workbench.action.terminal.kill",
            "workbench.action.terminal.new",
            "workbench.action.terminal.split",
            "workbench.action.terminal.toggleTerminal",
            "workbench.action.quickOpen",
            "workbench.action.findInFiles",
            "editor.action.commentLine",
            "editor.action.formatDocument"
        )
    }
}

# -- Section 7: Pi free-only routing -----------------------------------------
[Environment]::SetEnvironmentVariable('PI_FREE_ONLY', '1', 'User')
$env:PI_FREE_ONLY = '1'
$piDir = Join-Path $HOME ".pi"
New-Item -ItemType Directory -Path $piDir -Force | Out-Null
$freeJson = Join-Path $piDir "free.json"
if (-not (Test-Path $freeJson)) {
    Set-Content -Path $freeJson -Value '{"free": true}' -Encoding UTF8
}

# -- Section 8: launch VS Code on the workspace ------------------------------
$workspace = Join-Path $PWD "student_workspace"
New-Item -ItemType Directory -Path $workspace -Force | Out-Null

Write-Message "[>>] Configuracion completa." "Setup complete."
Write-Host ""
Write-Host "[i] Abriendo Visual Studio Code en student_workspace/..."
Write-Host "    Opening Visual Studio Code in student_workspace/..."
Write-Host ""

if (Get-Command code -ErrorAction SilentlyContinue) {
    & code $workspace
}

# -- Section 9: verification / version report --------------------------------
Write-Message "[*] Versiones instaladas:" "Installed versions:"
$tools = @(
    @{ Name = "node";  Args = @("--version") },
    @{ Name = "npm";   Args = @("--version") },
    @{ Name = "git";   Args = @("--version") },
    @{ Name = "pi";    Args = @("--version") },
    @{ Name = "opencode"; Args = @("--version") },
    @{ Name = "freebuff"; Args = @("--version") },
    @{ Name = "engram";  Args = @("--version") },
    @{ Name = "gentle-ai"; Args = @("--version") },
    @{ Name = "qodercli";  Args = @("--version") },
    @{ Name = "agy";    Args = @("--version") },
    @{ Name = "code";   Args = @("--version") }
)
foreach ($tool in $tools) {
    if (Get-Command $tool.Name -ErrorAction SilentlyContinue) {
        $out = & $tool.Name @($tool.Args) 2>&1
        Write-Host ("   " + $tool.Name + ": " + (($out | Select-Object -First 1) -join " "))
    }
}
$pyVer = & $venvPython --version 2>&1
Write-Host ("   python (venv): " + ($pyVer -join " "))
Write-Host ""
Write-Message "Para activar el entorno Python: .\.venv\Scripts\Activate.ps1" "To activate the Python environment: .\.venv\Scripts\Activate.ps1"

if (Test-IsNonInteractive) {
    return 0
}
Exit-WithPause -Code 0
}

if ($MyInvocation.InvocationName -ne '.') {
    exit (Invoke-Setup)
}
