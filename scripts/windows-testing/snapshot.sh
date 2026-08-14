#!/bin/sh
# ---------------------------------------------------------------------------
# snapshot.sh — disposable qcow2 overlay lifecycle for the Windows VM fixture.
#
# The external fixture keeps an immutable base image
# (/home/carlos/windows-snapshots/base/base.qcow2) that is NEVER booted
# directly. Every test run boots a disposable overlay (data.qcow2 in the VM
# storage directory) that records only the delta against the base. After the
# run the overlay is deleted, so disk usage per run is limited to the
# changes made inside the guest.
#
# Overridable environment:
#   WINDOWS_VM_DIR      VM storage directory (default /home/carlos/windows-vm)
#   WINDOWS_BASE_DIR    base image directory (default /home/carlos/windows-snapshots/base)
#
# Usage:
#   scripts/windows-testing/snapshot.sh create
#   scripts/windows-testing/snapshot.sh list
#   scripts/windows-testing/snapshot.sh delete
#
# The base image, overlay, SSH keys, and results live outside the
# repository. Never delete the protected post-OpenSSH master snapshot.
# ---------------------------------------------------------------------------
set -eu

VM_DIR="${WINDOWS_VM_DIR:-/home/carlos/windows-vm}"
BASE_DIR="${WINDOWS_BASE_DIR:-/home/carlos/windows-snapshots/base}"
BASE_IMAGE="$BASE_DIR/base.qcow2"
OVERLAY="$VM_DIR/data.qcow2"
COMPOSE_FILE="$VM_DIR/docker-compose.yml"

die() { echo "snapshot.sh: $*" >&2; exit 1; }

vm_running() {
    docker compose -f "$COMPOSE_FILE" ps --status running 2>/dev/null | grep -q windows
}

require_stopped() {
    if vm_running; then
        die "the windows container is running; stop it first: docker compose -f $COMPOSE_FILE stop"
    fi
}

require_base() {
    [ -f "$BASE_IMAGE" ] || die "base image not found: $BASE_IMAGE"
    [ -r "$BASE_IMAGE" ] || die "base image is not readable: $BASE_IMAGE"
}

cmd_create() {
    require_stopped
    require_base
    [ ! -e "$OVERLAY" ] || die "overlay already exists: $OVERLAY (run 'delete' first)"
    qemu-img create -q -f qcow2 -F qcow2 -b "$BASE_IMAGE" "$OVERLAY"
    echo "created disposable overlay: $OVERLAY"
}

cmd_list() {
    require_base
    echo "base:    $BASE_IMAGE (read-only, immutable)"
    if [ -e "$OVERLAY" ]; then
        backing=$(qemu-img info -f qcow2 --output=json "$OVERLAY" | grep -o '"backing-filename": "[^"]*"' | cut -d'"' -f4)
        echo "overlay: $OVERLAY (backing: $backing)"
    else
        echo "overlay: none"
    fi
}

cmd_delete() {
    require_stopped
    [ -e "$OVERLAY" ] || die "no overlay at $OVERLAY"
    rm -f "$OVERLAY"
    echo "deleted disposable overlay: $OVERLAY"
}

case "${1:-}" in
    create) cmd_create ;;
    list)   cmd_list ;;
    delete) cmd_delete ;;
    *) echo "usage: $0 {create|list|delete}" >&2; exit 2 ;;
esac
