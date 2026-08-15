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
#   WINDOWS_BASELINE     baseline name (default clean-bootstrap)
#   WINDOWS_SSH_KEY      SSH private key (default $WINDOWS_VM_DIR/.ssh/runner)
#   WINDOWS_SSH_USER     guest user (default Docker)
#   WINDOWS_SSH_HOST     guest endpoint (default 127.0.0.1)
#   WINDOWS_SSH_PORT     guest SSH port (default 2222)
#
# Usage:
#   scripts/windows-testing/vm-run.sh [--keep] [--baseline clean-bootstrap|prepared-runtime]
#
#   --keep keeps the overlay after the run for inspection; by default the
#   overlay is deleted so the fixture always returns to the clean base.
#   --baseline selects the base image the disposable overlay is backed by.
#
# Results land under $WINDOWS_VM_DIR/results/<run-id>/ (outside Git):
#   run-meta.json    guest engine/OS identity
#   windows-unit.xml JUnit output from Pester
#   scenarios.json   per-scenario summary parsed from the JUnit output
#   result.json      run verdict + failure class (snapshot|timeout|ssh|
#                    sut|assertion|environment|none)
#   RUN.md           human-readable run record
# ---------------------------------------------------------------------------
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
VM_DIR="${WINDOWS_VM_DIR:-/home/carlos/windows-vm}"
BASE_DIR="${WINDOWS_BASE_DIR:-/home/carlos/windows-snapshots/base}"
SSH_KEY="${WINDOWS_SSH_KEY:-$VM_DIR/.ssh/runner}"
SSH_USER="${WINDOWS_SSH_USER:-Docker}"
SSH_HOST="${WINDOWS_SSH_HOST:-127.0.0.1}"
SSH_PORT="${WINDOWS_SSH_PORT:-2222}"
SHARED_DIR="$VM_DIR/shared"
RESULTS_DIR="$VM_DIR/results"
SNAP="$ROOT/scripts/windows-testing/snapshot.sh"
COMPOSE_FILE="$VM_DIR/docker-compose.yml"

die() { echo "vm-run.sh: $*" >&2; exit 1; }

KEEP_OVERLAY=0
BASELINE="${WINDOWS_BASELINE:-clean-bootstrap}"
while [ $# -gt 0 ]; do
    case "$1" in
        --keep) KEEP_OVERLAY=1 ;;
        --baseline)
            [ $# -ge 2 ] || die "missing value for --baseline"
            BASELINE="$2"
            shift
            ;;
        --baseline=*) BASELINE="${1#--baseline=}" ;;
        *) die "unknown argument: $1 (expected --keep or --baseline=<name>)" ;;
    esac
    shift
done

case "$BASELINE" in
    clean-bootstrap)  BASE_NAME="base" ;;
    prepared-runtime) BASE_NAME="prepared-runtime" ;;
    *) die "unknown baseline: $BASELINE (expected clean-bootstrap or prepared-runtime)" ;;
esac
BASE_IMAGE="$BASE_DIR/$BASE_NAME.qcow2"

# snapshot.sh reads the baseline from the environment.
export WINDOWS_BASELINE="$BASELINE"

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

# Run-level result state, finalized by the EXIT trap into result.json.
PHASE="setup"
VERDICT="pass"
FAILURE_CLASS="none"
RUN_EXIT=0

echo "[vm-run] run=$RUNID revision=$REVISION baseline=$BASELINE"

classify_phase() {
    case "$PHASE" in
        snapshot) FAILURE_CLASS="snapshot" ;;
        sshwait)  FAILURE_CLASS="timeout" ;;
        run)      FAILURE_CLASS="ssh" ;;
        *)        FAILURE_CLASS="environment" ;;
    esac
}

record_result() {
    mkdir -p "$RESULTS_DIR/$RUNID" 2>/dev/null || return 0
    cat > "$RESULTS_DIR/$RUNID/result.json" <<EOF
{
  "run_id": "$RUNID",
  "revision": "$REVISION",
  "baseline": "$BASELINE",
  "verdict": "$VERDICT",
  "exit_code": $RUN_EXIT,
  "failure_class": "$FAILURE_CLASS",
  "phase": "$PHASE"
}
EOF
}

# shellcheck disable=SC2064
trap 'VERDICT=fail; RUN_EXIT=$?; classify_phase' ERR
trap 'record_result' EXIT

# 1. Fresh disposable overlay (fails safely if the VM is running).
PHASE="snapshot"
"$SNAP" create

# 2. Boot the fixture from the overlay.
PHASE="boot"
docker compose -f "$COMPOSE_FILE" up -d

# 3. Wait for the guest SSH control plane, not just the container process.
PHASE="sshwait"
printf '[vm-run] waiting for guest SSH'
booted=0
for _ in $(seq 1 40); do
    if ssh_cmd whoami >/dev/null 2>&1; then booted=1; break; fi
    printf .
    sleep 15
done
echo
if [ "$booted" != 1 ]; then
    VERDICT="fail"
    FAILURE_CLASS="timeout"
    RUN_EXIT=1
    echo "vm-run.sh: guest did not become reachable over SSH in time" >&2
    exit 1
fi

# 4. Stage the pinned revision through the shared bind mount (Z: in guest).
STAGE="$SHARED_DIR/windows-testing/$RUNID"
mkdir -p "$STAGE"
git -C "$ROOT" archive "$REVISION" | tar -x -C "$STAGE"
cat > "$STAGE/run.ps1" <<EOF
\$ErrorActionPreference = 'Continue'
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
PHASE="run"
set +e
ssh_cmd "net use Z: \\\\host.lan\\Data /persistent:no >nul && powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Z:\\windows-testing\\$RUNID\\run.ps1"
RUN_EXIT=$?
set -e

# Classify the suite outcome. A non-zero exit with a JUnit file means the
# suite ran and reported failing assertions; without it, the SUT scripts
# failed before Pester could produce results.
if [ "$RUN_EXIT" -ne 0 ]; then
    VERDICT="fail"
    if [ -f "$STAGE/results/windows-unit.xml" ]; then
        FAILURE_CLASS="assertion"
    else
        FAILURE_CLASS="sut"
    fi
else
    VERDICT="pass"
    FAILURE_CLASS="none"
fi

# 6. Collect results into the external results area.
PHASE="collect"
mkdir -p "$RESULTS_DIR/$RUNID"
cp "$STAGE/results/run-meta.json" "$RESULTS_DIR/$RUNID/run-meta.json" 2>/dev/null || true
cp "$STAGE/results/windows-unit.xml" "$RESULTS_DIR/$RUNID/windows-unit.xml" 2>/dev/null || true
cp "$STAGE/run.ps1" "$RESULTS_DIR/$RUNID/run.ps1"

if [ -f "$RESULTS_DIR/$RUNID/windows-unit.xml" ]; then
    python3 "$ROOT/scripts/windows-testing/parse-junit.py" \
        "$RESULTS_DIR/$RUNID/windows-unit.xml" \
        > "$RESULTS_DIR/$RUNID/scenarios.json" 2>/dev/null || true
fi

cat > "$RESULTS_DIR/$RUNID/RUN.md" <<EOF
# VM test run $RUNID

- Revision: $REVISION
- Base: $BASE_IMAGE
- Baseline: $BASELINE
- Fixture: dockurr/windows VM via $COMPOSE_FILE
- Suite exit code: $RUN_EXIT
- Verdict: $VERDICT
- Failure class: $FAILURE_CLASS
- Evidence: run-meta.json (guest engine/OS), windows-unit.xml (JUnit),
  scenarios.json (per-scenario summary), result.json (run verdict)
EOF

# 7. Graceful shutdown, then discard the disposable overlay.
PHASE="teardown"
docker compose -f "$COMPOSE_FILE" stop
if [ "$KEEP_OVERLAY" = 1 ]; then
    echo "[vm-run] keeping overlay for inspection"
else
    "$SNAP" delete
fi
rm -rf "$STAGE"

echo "[vm-run] done: results in $RESULTS_DIR/$RUNID"
exit "$RUN_EXIT"
