#!/bin/sh
# ---------------------------------------------------------------------------
# run-pester.sh — run the Windows bootstrap Pester suite in a container.
#
# The suite is written for PowerShell and runs under pwsh on Linux through
# the mcr.microsoft.com/powershell image with Pester 5 baked in. Evidence
# produced here is "PowerShell parses and unit seams behave"; it is not
# evidence for native Windows behavior (winget, WSL, Docker Desktop,
# execution policy).
#
# Usage:
#   scripts/windows-testing/run-pester.sh
# ---------------------------------------------------------------------------
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
IMAGE="docker-student-ide-pester:latest"
RESULTS_VOLUME="docker-student-ide-pester-results"

cd "$ROOT"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "[*] Building Pester test image ($IMAGE)..."
    docker build -t "$IMAGE" tests/windows
fi

docker volume inspect "$RESULTS_VOLUME" >/dev/null 2>&1 || \
    docker volume create "$RESULTS_VOLUME" >/dev/null

echo "[*] Running Pester suite on tests/windows/unit..."
docker run --rm \
    -v "$ROOT:/workspace:ro" \
    -w /workspace \
    -v "$RESULTS_VOLUME:/tmp/results" \
    -e PESTER_RESULTS_PATH=/tmp/results/windows-unit.xml \
    "$IMAGE" \
    -Command '$config = & ./tests/windows/pester.config.ps1; Invoke-Pester -Configuration $config; exit $LASTEXITCODE'
