# Agent Testing Rules

## Windows Testing

Read `docs/windows-automatic-testing-plan.md` and
`docs/windows-automatic-testing-agent-runbook.md` before changing the Windows
bootstrap path.

Authoritative test source belongs in `tests/windows/`. Host-side VM adapters
belong in `scripts/windows-testing/`. The external directory
`/home/carlos/windows-vm` contains runtime state only and must never become a
source or result dependency committed to Git.

Do not claim native Windows, WSL2, or Docker Desktop coverage from Linux static
checks or from the dockur/windows SSH fixture. Report those as separate
evidence layers.

Before starting review, run `gentle-ai review status` with explicit selection
of intended untracked files and execute the exact transition it emits. Do not
reuse a stale target identity or hand-write a replacement review command.

Keep test artifacts, credentials, snapshots, VM images, and raw environment
files outside the repository. Separate implementation commits from test-plan
and test-harness commits.
