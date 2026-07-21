#!/bin/sh
# ---------------------------------------------------------------------------
# docker-student-ide — One-liner install (macOS / Linux)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/CarlosAndres12/docker-student-ide/main/scripts/install.sh | bash
#
#   # With arguments forwarded to start.sh:
#   curl -fsSL <url> | bash -s -- -d
#   curl -fsSL <url> | bash -s -- --build
# ---------------------------------------------------------------------------
set -e

REPO_URL="https://github.com/CarlosAndres12/docker-student-ide.git"
REPO_DIR="docker-student-ide"

# -- Check for git -----------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
    echo "Error: git is required. Install it first."
    echo "  macOS:  brew install git"
    echo "  Ubuntu/Debian: sudo apt install git"
    echo "  Fedora: sudo dnf install git"
    exit 1
fi

# -- Already in repo? ---------------------------------------------------------
if [ -f "start.sh" ] && [ -f "docker-compose.yml" ]; then
    echo "[*] Already in docker-student-ide. Running start.sh..."
    exec sh start.sh "$@"
fi

# -- Clone --------------------------------------------------------------------
echo "[*] Cloning docker-student-ide..."
if [ -d "$REPO_DIR" ]; then
    echo "[*] Directory $REPO_DIR already exists. Using existing clone."
else
    git clone "$REPO_URL" "$REPO_DIR" || {
        echo "Error: Failed to clone repository. Check your internet connection."
        exit 1
    }
fi

cd "$REPO_DIR"

# -- Run ----------------------------------------------------------------------
echo "[*] Starting docker-student-ide..."
exec sh start.sh "$@"
