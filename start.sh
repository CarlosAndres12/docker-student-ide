#!/bin/sh
# =============================================================================
# start.sh — docker-student-ide Bootstrap Script (macOS / Linux / Git-Bash)
# =============================================================================
# This script:
#   1. Detects your operating system (macOS, Linux, or Windows/Git-Bash).
#   2. Checks if Docker is installed.  If missing, installs it:
#        - macOS:   via Homebrew (Docker Desktop)
#        - Linux:   via apt (Debian/Ubuntu), dnf (Fedora), or pacman (Arch)
#        - Windows: prints a message directing you to use start.ps1
#   3. Checks if the Docker daemon is running; waits or prints guidance.
#   4. Checks for `docker compose` (v2) or falls back to `docker-compose` (v1).
#   5. Auto-detects your host UID/GID and writes them into .env (idempotent).
#   6. Forwards ALL arguments to `docker compose up "$@"`.
#
# After running this script, Docker is installed (if it wasn't), file ownership
# in student_workspace/ is mapped to your host user, and code-server starts.
#
# MANUAL FALLBACKS:
#   - If `id` is not available: set PUID=1000 and PGID=1000 in .env manually.
#   - If `docker` could not be auto-installed: install Docker from
#     https://docs.docker.com/engine/install/ and run this script again.
# =============================================================================

# ── Section 1: OS Detection ──────────────────────────────────────────────────
detect_os() {
    OS="unknown"
    case "$(uname -s)" in
        Darwin*)  OS="macos"   ;;
        Linux*)   OS="linux"   ;;
        MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
    esac
    echo "$OS"
}
OS=$(detect_os)

echo "🔍 Sistema detectado / OS detected: $OS"

# ── Section 2: Check / Install Docker ────────────────────────────────────────
if command -v docker >/dev/null 2>&1; then
    echo "✅ Docker ya está instalado / Docker is already installed."
else
    echo "🔍 Docker no encontrado. Instalando..."
    echo "   Docker not found. Installing..."

    case "$OS" in
        macos)
            # Install Homebrew if missing
            if ! command -v brew >/dev/null 2>&1; then
                echo "🍺 Instalando Homebrew..."
                echo "   Installing Homebrew (official one-liner)..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
                    echo "❌ Error al instalar Homebrew."
                    echo "   Instálalo manualmente desde https://brew.sh/ y vuelve a ejecutar este script."
                    exit 1
                }
                # Ensure brew is on PATH
                if command -v brew >/dev/null 2>&1; then
                    :
                elif [ -x /opt/homebrew/bin/brew ]; then
                    eval "$(/opt/homebrew/bin/brew shellenv)"
                elif [ -x /usr/local/bin/brew ]; then
                    eval "$(/usr/local/bin/brew shellenv)"
                fi
            fi
            echo "🍺 Instalando Docker Desktop via Homebrew..."
            echo "   Installing Docker Desktop via Homebrew..."
            brew install --cask docker || {
                echo "❌ Error al instalar Docker Desktop."
                echo "   Instálalo manualmente desde https://docs.docker.com/desktop/install/mac-install/"
                exit 1
            }
            echo ""
            echo "⚠️  Docker Desktop se instaló en /Applications."
            echo "   ABRE Docker Desktop desde tu carpeta de Aplicaciones y espera a que el ícono"
            echo "   en la barra de menú muestre 'Docker Desktop is running'. Luego ejecuta este"
            echo "   script de nuevo."
            echo ""
            echo "   Docker Desktop was installed in /Applications. Open it from your Applications"
            echo "   folder and wait for the menu-bar icon to say 'Docker Desktop is running'."
            echo "   Then run this script again."
            exit 0
            ;;
        linux)
            # Debian / Ubuntu
            if command -v apt-get >/dev/null 2>&1; then
                echo "🐧 Detectado: Debian/Ubuntu (apt). Instalando docker.io..."
                echo "   Detected: Debian/Ubuntu (apt). Installing docker.io..."
                sudo apt-get update -qq
                sudo apt-get install -y -qq docker.io docker-compose-plugin || {
                    echo "❌ Error al instalar Docker via apt."
                    echo "   Instálalo manualmente desde https://docs.docker.com/engine/install/"
                    exit 1
                }
                sudo systemctl enable docker 2>/dev/null || true
                sudo systemctl start docker 2>/dev/null || true
                # Add user to docker group
                if ! groups "$(whoami)" | grep -q '\bdocker\b'; then
                    sudo usermod -aG docker "$(whoami)"
                    echo "👤 Usuario agregado al grupo 'docker'."
                    echo "   User added to the 'docker' group."
                    echo "   👉 CIERRA SESIÓN y vuelve a entrar (o reinicia) para que esto tenga efecto."
                    echo "      Log out and back in (or reboot) for group changes to take effect."
                fi
            # Fedora / RHEL
            elif command -v dnf >/dev/null 2>&1; then
                echo "🐧 Detectado: Fedora/RHEL (dnf). Instalando docker..."
                echo "   Detected: Fedora/RHEL (dnf). Installing docker..."
                sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || {
                    echo "❌ Error al instalar Docker via dnf."
                    echo "   Instálalo manualmente desde https://docs.docker.com/engine/install/"
                    exit 1
                }
                sudo systemctl enable docker 2>/dev/null || true
                sudo systemctl start docker 2>/dev/null || true
                # Add user to docker group
                if ! groups "$(whoami)" | grep -q '\bdocker\b'; then
                    sudo usermod -aG docker "$(whoami)"
                    echo "👤 Usuario agregado al grupo 'docker'."
                    echo "   User added to the 'docker' group."
                    echo "   👉 CIERRA SESIÓN y vuelve a entrar (o reinicia) para que esto tenga efecto."
                    echo "      Log out and back in (or reboot) for group changes to take effect."
                fi
            # Arch Linux
            elif command -v pacman >/dev/null 2>&1; then
                echo "🐧 Detectado: Arch Linux (pacman). Instalando docker..."
                echo "   Detected: Arch Linux (pacman). Installing docker..."
                sudo pacman -S --noconfirm docker docker-compose || {
                    echo "❌ Error al instalar Docker via pacman."
                    echo "   Instálalo manualmente desde https://wiki.archlinux.org/title/Docker"
                    exit 1
                }
                sudo systemctl enable docker 2>/dev/null || true
                sudo systemctl start docker 2>/dev/null || true
                # Add user to docker group
                if ! groups "$(whoami)" | grep -q '\bdocker\b'; then
                    sudo usermod -aG docker "$(whoami)"
                    echo "👤 Usuario agregado al grupo 'docker'."
                    echo "   User added to the 'docker' group."
                    echo "   👉 CIERRA SESIÓN y vuelve a entrar (o reinicia) para que esto tenga efecto."
                    echo "      Log out and back in (or reboot) for group changes to take effect."
                fi
            else
                echo "❌ No se pudo detectar el gestor de paquetes de Linux."
                echo "   Could not detect your Linux package manager."
                echo "   Instala Docker manualmente desde https://docs.docker.com/engine/install/"
                echo "   Luego ejecuta este script de nuevo / then run this script again."
                exit 1
            fi
            ;;
        windows)
            echo "🪟 Git-Bash detectado. Docker Desktop debe instalarse en Windows."
            echo "   Git-Bash detected. Docker Desktop must be installed on Windows."
            echo "   Ejecuta este comando en PowerShell como Administrador:"
            echo "   Run this command in PowerShell as Administrator:"
            echo ""
            echo "   .\\start.ps1"
            echo ""
            echo "   O descárgalo manualmente desde / Or download from:"
            echo "   https://docs.docker.com/desktop/install/windows-install/"
            echo ""
            echo "Si ya tienes Docker instalado, el script continuará..."
            echo "If Docker is already installed, the script will continue..."
            # Don't exit — docker might be on PATH via Docker Desktop
            ;;
        *)
            echo "❌ Sistema operativo no soportado / Unsupported OS: $OS"
            echo "   Instala Docker manualmente desde https://docs.docker.com/engine/install/"
            exit 1
            ;;
    esac
fi

# ── Section 3: Check Docker Compose (v2 vs v1 fallback) ──────────────────────
COMPOSE_CMD=""
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    echo "✅ docker compose (v2) disponible / available."
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
    echo "⚠️  docker-compose (v1) encontrado. Se usará como fallback."
    echo "   docker-compose (v1) found. Will use it as fallback."
    echo "   Considera actualizar a docker compose v2: https://docs.docker.com/compose/install/"
else
    echo "❌ No se encontró docker-compose ni docker compose."
    echo "   Neither docker-compose nor docker compose was found."
    echo "   Asegúrate de que Docker esté correctamente instalado."
    echo "   Make sure Docker is properly installed."
    exit 1
fi

# ── Section 4: Check if Docker daemon is running ─────────────────────────────
echo "⏳ Verificando que el servicio Docker esté corriendo..."
echo "   Checking that the Docker daemon is running..."

if ! docker info >/dev/null 2>&1; then
    echo "⚠️  El servicio Docker no está respondiendo."
    echo "   The Docker daemon is not responding."

    # Try to auto-start the daemon
    case "$OS" in
        linux)
            echo "   🐧 Intentando iniciar el servicio Docker automáticamente..."
            echo "      Trying to auto-start the Docker daemon..."
            if command -v systemctl >/dev/null 2>&1; then
                if [ "$(id -u)" -eq 0 ]; then
                    systemctl start docker 2>/dev/null || systemctl start docker.service 2>/dev/null || true
                else
                    sudo systemctl start docker 2>/dev/null || sudo systemctl start docker.service 2>/dev/null || true
                fi
            elif command -v service >/dev/null 2>&1; then
                if [ "$(id -u)" -eq 0 ]; then
                    service docker start 2>/dev/null || true
                else
                    sudo service docker start 2>/dev/null || true
                fi
            fi
            MAX_WAIT=120
            ;;
        macos)
            echo "   🍎 Intentando abrir Docker Desktop automáticamente..."
            echo "      Trying to auto-launch Docker Desktop..."
            open -a Docker 2>/dev/null || true
            MAX_WAIT=120
            ;;
        windows)
            echo "   🪟 Abre Docker Desktop desde el menú Inicio."
            echo "      Open Docker Desktop from your Start Menu."
            echo "   ⏳ Espera a que el ícono muestre 'Running' continuará automáticamente..."
            echo "      Once the icon shows 'Running', the script will continue..."
            MAX_WAIT=120
            ;;
    esac

    # Poll docker info until ready
    echo "   ⏳ Esperando a que Docker esté listo (hasta ${MAX_WAIT}s)..."
    echo "      Waiting for Docker to be ready (up to ${MAX_WAIT}s)..."
    ELAPSED=0
    while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
        if docker info >/dev/null 2>&1; then
            break
        fi
        sleep 5
        ELAPSED=$((ELAPSED + 5))
        if [ $((ELAPSED % 20)) -eq 0 ]; then
            printf "   ... %s/%ss\n" "$ELAPSED" "$MAX_WAIT"
        fi
    done

    # Final check
    if docker info >/dev/null 2>&1; then
        echo "   ✅ Docker respondió después de ${ELAPSED}s."
        echo "      Docker responded after ${ELAPSED}s."
    else
        echo "❌ Docker no respondió después de ${MAX_WAIT}s."
        echo "   Docker did not respond after ${MAX_WAIT}s."
        echo ""
        case "$OS" in
            linux)
                # Check if it's a permissions issue
                if groups "$(whoami)" 2>/dev/null | grep -q '\bdocker\b'; then
                    echo "   🔍 Estás en el grupo 'docker' pero el daemon no responde."
                    echo "      You're in the 'docker' group but the daemon isn't responding."
                    echo "   👉 Verifica el servicio: sudo systemctl status docker"
                    echo "      Check the service: sudo systemctl status docker"
                    echo "   👉 O revisa los logs: sudo journalctl -u docker -n 50"
                    echo "      Or check the logs: sudo journalctl -u docker -n 50"
                else
                    echo "   🔍 Puede que necesites permisos. Agrega tu usuario al grupo 'docker':"
                    echo "      You may need permissions. Add your user to the 'docker' group:"
                    echo "        sudo usermod -aG docker \$(whoami)"
                    echo "      Luego CIERRA SESIÓN y vuelve a entrar."
                    echo "      Then LOG OUT and log back in."
                fi
                ;;
            macos)
                echo "   🔍 Abre Docker Desktop manualmente desde /Applications."
                echo "      Open Docker Desktop manually from /Applications."
                echo "   Asegúrate de que el ícono en la barra de menú muestre 'Running'."
                echo "   Make sure the menu bar icon shows 'Running'."
                ;;
            windows)
                echo "   🔍 Abre Docker Desktop desde el menú Inicio."
                echo "      Open Docker Desktop from the Start Menu."
                echo "   Asegúrate de que el ícono en la bandeja del sistema muestre 'Running'."
                echo "   Make sure the system tray icon shows 'Running'."
                ;;
        esac
        exit 1
    fi
fi
echo "✅ Docker está funcionando / Docker is running."

# ── Section 5: Detect host UID/GID (existing logic) ─────────────────────────
HOST_UID=$(id -u 2>/dev/null || echo 1000)
HOST_GID=$(id -g 2>/dev/null || echo 1000)

# ── Section 6: Read current values from .env (if it exists) ─────────────────
CURRENT_PUID=""
CURRENT_PGID=""
if [ -f .env ]; then
    CURRENT_PUID=$(grep '^PUID=' .env | head -n 1 | cut -d= -f2)
    CURRENT_PGID=$(grep '^PGID=' .env | head -n 1 | cut -d= -f2)
fi

# ── Section 7: Update .env if values differ (idempotent) ────────────────────
NEEDS_UPDATE=0
if [ "$HOST_UID" != "$CURRENT_PUID" ] || [ "$HOST_GID" != "$CURRENT_PGID" ]; then
    NEEDS_UPDATE=1
fi

if [ "$NEEDS_UPDATE" -eq 1 ]; then
    # Create .env from .env.example if it doesn't exist
    if [ ! -f .env ]; then
        cp .env.example .env 2>/dev/null || touch .env
    fi

    # Update PUID line (replace if exists, append if not)
    if grep '^PUID=' .env >/dev/null 2>&1; then
        sed "s/^PUID=.*/PUID=$HOST_UID/" .env > .env.tmp && mv .env.tmp .env
    else
        echo "PUID=$HOST_UID" >> .env
    fi

    # Update PGID line (replace if exists, append if not)
    if grep '^PGID=' .env >/dev/null 2>&1; then
        sed "s/^PGID=.*/PGID=$HOST_GID/" .env > .env.tmp && mv .env.tmp .env
    else
        echo "PGID=$HOST_GID" >> .env
    fi

    echo "📝 start.sh: Updated .env with PUID=$HOST_UID PGID=$HOST_GID"
fi

# ── Section 8: Run docker compose ────────────────────────────────────────────
echo "🚀 Iniciando docker-student-ide..."
echo "   Starting docker-student-ide..."
echo ""
echo "🌐 Accede al IDE en: http://localhost:8443"
echo "   Access the IDE at: http://localhost:8443"
echo ""

if [ "$COMPOSE_CMD" = "docker compose" ]; then
    exec docker compose up "$@"
else
    exec docker-compose up "$@"
fi
