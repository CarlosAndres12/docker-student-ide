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
| Human architecture plan | `docs/windows-automatic-testing-plan.md` |

The VM image, snapshots, SSH keys, known-hosts file, credentials, and test
results are external artifacts. Keep them under the controlled VM area, never
under Git.

## Evidence Rules

- `bash -n` and `docker compose config` prove only Linux-visible contracts.
- Pester contract tests prove source-level invariants when run with Pester 5.
- SSH proves transport and guest control, not native Windows bootstrap behavior.
- Native Windows + WSL2 + Docker Desktop tests are required for platform claims.
- VM, SSH, snapshot, and timeout failures are infrastructure failures.

## Phase Order

1. Run the Linux static checks and inspect the worktree.
2. Run Pester contracts on a Windows host with `$config = & .\tests\windows\pester.config.ps1; Invoke-Pester -Configuration $config`.
3. Use the support helpers under `tests/windows/support/` for temporary workspaces, command fakes, and child-process results.
4. Extract remaining side-effecting bootstrap operations behind testable functions before expanding mocked unit coverage.
5. Replace pending unit scenarios with deterministic tests; pending native/VM scenarios are not coverage claims.
6. Add disposable native Windows integration only after the unit suite is deterministic.
7. Add VM snapshot/restore and SSH orchestration under `scripts/windows-testing/`.
8. Add protected CI jobs only after cleanup and credential boundaries are reviewed.

## Current Limitations

The Linux development host may not have `pwsh`, so PowerShell execution must be
reported as unavailable rather than passed by assumption. The current external
VM has verified SSH/OpenSSH control-plane evidence, but it is not evidence for
Docker Desktop or WSL2 integration.

The scripts support `DOCKER_STUDENT_IDE_NONINTERACTIVE=1`. Use it for automated
runs so `Read-Host` pauses do not hang SSH or CI. This mode declines optional
WSL installation and still returns the script's exit code.

## Review and Cleanup

Use `gentle-ai review status` to obtain the current target and explicitly select
intended untracked files. Execute only the exact transition emitted by status.
After every scenario, collect stdout, stderr, exit code, fixture identity, and
cleanup/restore status. Never replace `data.img` while the VM is running.
