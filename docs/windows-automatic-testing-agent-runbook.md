# Windows Testing Agent Runbook

This runbook is the operational companion to
`docs/windows-automatic-testing-plan.md`. It tells an agent what may be
claimed, where code belongs, and how to progress safely.

## Source Layout

| Purpose | Repository location |
|---|---|
| Pester configuration | `tests/windows/pester.config.ps1` |
| Static and unit tests | `tests/windows/unit/` |
| Native Windows tests | `tests/windows/integration/` |
| Test fixtures and helpers | `tests/windows/fixtures/`, `tests/windows/support/` |
| Host VM and SSH adapters | `scripts/windows-testing/` |
| Overlay lifecycle | `scripts/windows-testing/snapshot.sh` |
| VM run orchestration | `scripts/windows-testing/vm-run.sh` |
| Docker Pester runner | `tests/windows/Dockerfile`, `scripts/windows-testing/run-pester.sh` |
| Human architecture plan | `docs/windows-automatic-testing-plan.md` |

The VM base image, overlays, snapshots, SSH keys, known-hosts file,
credentials, and test results are external artifacts. Keep them under the
controlled VM area (`/home/carlos/windows-vm`, `/home/carlos/windows-snapshots`),
never under Git. The protected post-OpenSSH master snapshot must never be
deleted.

## Evidence Rules

- `bash -n` and `docker compose config` prove only Linux-visible contracts.
- Pester contract tests prove source-level invariants when run with Pester 5.
- The Docker runner proves the PowerShell code parses and unit seams behave.
- `vm-run.sh` proves the scripts parse and the unit seams behave under Windows
  PowerShell 5.1 on the Windows 11 fixture. It does not yet prove winget, WSL,
  or Docker Desktop behavior.
- SSH proves transport and guest control, not native Windows bootstrap behavior.
- Native Windows + WSL2 + Docker Desktop tests are required for platform claims.
- VM, SSH, snapshot, and timeout failures are infrastructure failures.

## Phase Order

1. Run the Linux static checks and inspect the worktree.
2. Run the unit suite in the container:
   `scripts/windows-testing/run-pester.sh`.
3. Run the same suite on real Windows through the VM fixture:
   `scripts/windows-testing/vm-run.sh`. Results land in
   `/home/carlos/windows-vm/results/<run-id>/`.
4. Use the support helpers under `tests/windows/support/` for temporary workspaces, command fakes, and child-process results.
5. Extract remaining side-effecting bootstrap operations behind testable functions before expanding mocked unit coverage.
6. Replace pending unit scenarios with deterministic tests; pending native/VM scenarios are not coverage claims.
7. Add disposable native Windows integration only after the unit suite is deterministic.
8. Add protected CI jobs only after cleanup and credential boundaries are reviewed.

## Current Limitations

The Linux development host may not have `pwsh`, so PowerShell execution must be
reported as unavailable rather than passed by assumption. The VM fixture is the
execution path for real Windows.

The VM boots only from a disposable overlay over the immutable base. Never
start the VM storage directory without an overlay: dockurr would create a new
blank disk and reinstall Windows. The base image is read-only and must not be
booted directly; maintenance changes go through a temporary overlay followed
by `qemu-img commit`.

Windows drive mappings are per-logon-session, so `Z:` must be mapped with
`net use` inside the same SSH session that runs the suite. The suite must run
with `-NoProfile -NonInteractive -ExecutionPolicy Bypass`: the default
Restricted policy blocks Pester's format files even without a Mark-of-the-Web.

The scripts support `DOCKER_STUDENT_IDE_NONINTERACTIVE=1`. Use it for automated
runs so `Read-Host` pauses do not hang SSH or CI. This mode declines optional
WSL installation and still returns the script's exit code.

## Review and Cleanup

Use `gentle-ai review status` to obtain the current target and explicitly select
intended untracked files. Execute only the exact transition emitted by status.
After every scenario, collect stdout, stderr, exit code, fixture identity, and
cleanup/restore status. Never replace `data.img` while the VM is running.
