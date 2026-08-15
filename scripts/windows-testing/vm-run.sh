#!/bin/sh
# ---------------------------------------------------------------------------
# vm-run.sh — run the Windows Pester suite on the dockurr/windows VM fixture.
#
# One run = fresh disposable overlay -> boot -> stage the pinned revision ->
# run the suite over SSH -> collect results -> graceful shutdown -> delete
# the overlay. The immutable base image is never booted directly.
#
# Evidence produced here is real Windows execution: the suite runs under
# Windows PowerShell 5.1 on Windows 11. It proves the bootstrap scripts
# parse and the unit seams behave on Windows. It does NOT yet prove winget,
# WSL, or Docker Desktop behavior (those need the prepared-runtime baseline).
#
# Overridable environment:
#   WINDOWS_VM_DIR       VM storage directory (default /home/carlos/windows-vm)
#   WINDOWS_SSH_KEY      SSH private key (default $WINDOWS_VM_DIR/.ssh/runner)
#   WINDOWS_SSH_USER     guest user (default Docker)
#   WINDOWS_SSH_HOST     guest endpoint (default 127.0.0.1)
#   WINDOWS_SSH_PORT     guest SSH port (default 2222)
#
# Usage:
#   scripts/windows-testing/vm-run.sh [--keep]
#
#   --keep keeps the overlay after the run for inspection; by default the
#   overlay is deleted so the fixture always returns to the clean base.
#
# Results land under $WINDOWS_VM_DIR/results/<run-id>/ (outside Git).
# ---------------------------------------------------------------------------
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
VM_DIR="${WINDOWS_VM_DIR:-/home/carlos/windows-vm}"
BASE_DIR="${WINDOWS_BASE_DIR:-/home/carlos/windows-snapshots/base}"
BASE_IMAGE="$BASE_DIR/base.qcow2"
SSH_KEY="${WINDOWS_SSH_KEY:-$VM_DIR/.ssh/runner}"
SSH_USER="${WINDOWS_SSH_USER:-Docker}"
SSH_HOST="${WINDOWS_SSH_HOST:-127.0.0.1}"
SSH_PORT="${WINDOWS_SSH_PORT:-2222}"
SHARED_DIR="$VM_DIR/shared"
RESULTS_DIR="$VM_DIR/results"
SNAP="$ROOT/scripts/windows-testing/snapshot.sh"
COMPOSE_FILE="$VM_DIR/docker-compose.yml"

KEEP_OVERLAY=0
[ "${1:-}" = "--keep" ] && KEEP_OVERLAY=1

die() { echo "vm-run.sh: $*" >&2; exit 1; }
[ -f "$SSH_KEY" ] || die "runner SSH key not found: $SSH_KEY"

ssh_cmd() {
    ssh -i "$SSH_KEY" -p "$SSH_PORT" \
        -o BatchMode=yes -o IdentitiesOnly=yes \
        -o UserKnownHostsFile="$VM_DIR/.ssh/known_hosts" \
        -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=15 -o LogLevel=ERROR \
        "$SSH_USER@$SSH_HOST" "$@"
}

RUNID="run-$(date -u +%Y%m%dT%H%M%SZ)"
REVISION="$(git -C "$ROOT" rev-parse HEAD)"
echo "[vm-run] run=$RUNID revision=$REVISION"

# 1. Fresh disposable overlay (fails safely if the VM is running).
"$SNAP" create

# 2. Boot the fixture from the overlay.
docker compose -f "$COMPOSE_FILE" up -d

# 3. Wait for the guest SSH control plane, not just the container process.
printf '[vm-run] waiting for guest SSH'
booted=0
for _ in $(seq 1 40); do
    if ssh_cmd whoami >/dev/null 2>&1; then booted=1; break; fi
    printf .
    sleep 15
done
echo
[ "$booted" = 1 ] || die "guest did not become reachable over SSH in time"

# 4. Stage the pinned revision through the shared bind mount (Z: in guest).
STAGE="$SHARED_DIR/windows-testing/$RUNID"
mkdir -p "$STAGE"
git -C "$ROOT" archive "$REVISION" | tar -x -C "$STAGE"
cat > "$STAGE/run.ps1" <<EOF
\$ErrorActionPreference = 'Stop'
\$repoRoot = 'Z:\windows-testing\\$RUNID'
New-Item -ItemType Directory -Path (Join-Path \$repoRoot 'results') -Force | Out-Null
\$meta = [pscustomobject]@{
    run_id   = '$RUNID'
    revision = '$REVISION'
    engine   = \$PSVersionTable.PSVersion.ToString()
    os       = (Get-CimInstance Win32_OperatingSystem).Caption
    os_build = [Environment]::OSVersion.Version.ToString()
    hostname = \$env:COMPUTERNAME
    started  = (Get-Date).ToUniversalTime().ToString('o')
}
\$meta | ConvertTo-Json | Set-Content -Path (Join-Path \$repoRoot 'results\run-meta.json')
\$env:PESTER_TEST_PATH = Join-Path \$repoRoot 'tests\windows'
\$env:PESTER_RESULTS_PATH = Join-Path \$repoRoot 'results\windows-unit.xml'
Set-Location \$repoRoot
\$config = & (Join-Path \$repoRoot 'tests\windows\pester.config.ps1')
Invoke-Pester -Configuration \$config
EOF

# 5. Run the suite. Drive mappings are per-logon-session on Windows and do
#    not survive across separate ssh calls, so map Z: and execute the runner
#    inside the SAME SSH session.
set +e
ssh_cmd "net use Z: \\\\host.lan\\Data /persistent:no >nul && powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Z:\\windows-testing\\$RUNID\\run.ps1"
RUN_EXIT=$?
set -e

# 6. Collect results into the external results area.
mkdir -p "$RESULTS_DIR/$RUNID"
cp "$STAGE/results/run-meta.json" "$RESULTS_DIR/$RUNID/run-meta.json" 2>/dev/null || true
cp "$STAGE/results/windows-unit.xml" "$RESULTS_DIR/$RUNID/windows-unit.xml" 2>/dev/null || true
cp "$STAGE/run.ps1" "$RESULTS_DIR/$RUNID/run.ps1"
cat > "$RESULTS_DIR/$RUNID/RUN.md" <<EOF
# VM test run $RUNID

- Revision: $REVISION
- Base: $BASE_IMAGE
- Fixture: dockurr/windows VM via $COMPOSE_FILE
- Suite exit code: $RUN_EXIT
- Evidence: run-meta.json (guest engine/OS), windows-unit.xml (JUnit)
EOF

# 7. Graceful shutdown, then discard the disposable overlay.
docker compose -f "$COMPOSE_FILE" stop
if [ "$KEEP_OVERLAY" = 1 ]; then
    echo "[vm-run] keeping overlay for inspection"
else
    "$SNAP" delete
fi
rm -rf "$STAGE"

echo "[vm-run] done: results in $RESULTS_DIR/$RUNID"
exit "$RUN_EXIT"
