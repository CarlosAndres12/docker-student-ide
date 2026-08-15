# Windows Automatic Testing Plan

This document defines an incremental test system for the Windows bootstrap path
of the Docker Compose distribution. Phase 0 and the first static Pester
contracts are now implemented; native Windows execution, VM orchestration, and
CI remain future phases.

## Current Baseline

| Area | Verified state | Consequence for the plan |
|---|---|---|
| Repository | `scripts/install.ps1`, `start.ps1`, `scripts/install.sh`, and `start.sh` are the bootstrap entry points. | Tests must cover both the PowerShell path and shell-wrapper parity where behavior overlaps. |
| Windows tests | A tracked static-contract Pester suite exists; there is no native Windows harness or Windows CI runner. | Contract tests are implemented; mocked side-effect tests, native integration, and CI remain future work. |
| External fixture | A live `dockur/windows` VM exists at `/home/carlos/windows-vm`. It runs Windows 11 (10.0.26200) with 8 GB RAM, 4 vCPU, and a disposable qcow2 overlay over an immutable base image. | Use it for controlled runtime proof, not as an implicit repository dependency. |
| VM control plane | The host `/shared` bind mount appears as `Z:` in the interactive guest session. OpenSSH is installed and verified; a dedicated runner key authenticates over `127.0.0.1:2222`. | The host can stage files and run noninteractive guest commands over SSH; SSH sessions map `Z:` per session via `net use`. |
| Real-Windows run | The Pester suite runs on the VM under Windows PowerShell 5.1 (`scripts/windows-testing/vm-run.sh`): 28 passed, 0 failed, 4 skipped (1 fixture-dependent skip, 3 pending runtime scenarios). | This proves the bootstrap scripts parse, the unit seams behave, and the execution-policy bypass seam works on real Windows. It does not prove winget, WSL, or Docker Desktop behavior. |
| Fixture state | The base image carries a real Git 2.55 installation from earlier provisioning; scenarios that need Git absent enforce the premise with function shadows. | Tests must not depend on fixture contents; enforce premises explicitly. |

### Current implementation boundary

The current uncommitted change set under review includes the Windows bootstrap
scripts, their shell counterparts, Docker image cleanup, deployment
documentation, and this testing plan. The tracked testing implementation lives
under `tests/windows/`; host-side VM adapters live under
`scripts/windows-testing/`. No test source is authoritative
inside `/home/carlos/windows-vm`.

The following evidence is currently valid:

- Linux static checks: shell syntax and `docker compose config`.
- Container Pester run: the PowerShell code parses and the unit seams behave under pwsh on Linux.
- Real-Windows VM run: the same suite executes under Windows PowerShell 5.1 on the Windows 11 fixture with key-based SSH orchestration.
- External VM checks: SSH transport, guest identity, OpenSSH service state, shared-directory staging, nested VMX exposure, and snapshot/restore lifecycle.

The following evidence is not yet available:

- PowerShell execution on the Linux development host (still unavailable; the VM runner is the execution path).
- Native Windows + WSL2 + Docker Desktop integration.
- A Windows CI runner or scheduled external-VM job.

The external VM snapshot, credentials, image, and result artifacts remain
outside Git. The VM must not be treated as a substitute for native Windows
coverage.

The VM proves real Windows PowerShell execution and controlled guest
orchestration. It does **not** yet replace coverage on native Windows with WSL2
and Docker Desktop. Those layers exercise the platform dependencies that the
current `dockur/windows` fixture does not prove by itself and must be covered
separately (the fixture exposes VMX, so they are reachable, but they are not
covered yet).

## Target Architecture

```text
Host coordinator
  -> snapshot/restore adapter
  -> SSH adapter on 127.0.0.1:2222
  -> Windows test runner
       -> install.ps1 / start.ps1
       -> WSL2 and Docker Desktop
       -> docker compose and the code-server runtime
```

The test system should use the smallest layer that can prove a behavior. A
failure in the VM controller or SSH transport must be reported as an
infrastructure failure, not as a product failure.

| Layer | Fixture | Responsibilities | Cadence |
|---|---|---|---|
| Static contracts | Linux host | Check PowerShell and shell file presence, shell syntax, required command shapes, and `docker compose config`. Do not claim this proves PowerShell execution. | Every change |
| PowerShell unit tests (container) | `mcr.microsoft.com/powershell` with Pester 5 | Run the deterministic unit suite under pwsh on Linux. Proves the PowerShell code parses and the unit seams behave. Does not prove native Windows behavior. | Every change touching bootstrap scripts |
| PowerShell unit tests (native) | PowerShell with Pester 5, mocked external commands | Exercise branching, exit codes, argument forwarding, `.env` mutation, bounded waits, and user-facing diagnostics without installing software or changing a real machine. | Every change |
| Native bootstrap integration | Disposable Windows 11 with WSL2 and Docker Desktop | Prove the real `install.ps1` and `start.ps1` behavior across execution policy, WSL, Docker Desktop, Compose, and reboot/state transitions. | Pull request or protected-branch gate once stable |
| External VM runtime proof | `/home/carlos/windows-vm` through SSH | Prove guest reachability, staging, process execution, snapshot recovery, and selected Compose/runtime smoke checks. | Manual first, then scheduled/nightly |
| Shell parity | Linux and, where available, macOS | Keep `install.sh` and `start.sh` behavior covered for shared contracts such as Compose invocation, argument forwarding, and `.env` updates. | Every change touching shell wrappers |

### Test framework choice

Pester 5 is the recommended unit and orchestration assertion framework because
the system under test is PowerShell. The suite should mock `Get-Command`,
`Start-Process`, `Read-Host`, `docker`, `wsl`, `winget`, `choco`, `git`, file
system operations, and sleeps. Tests must assert calls and arguments, not only
printed text.

If adding Pester is not acceptable, use a small PowerShell runner with explicit
assertion functions and child-process tests. The replacement must still provide
isolated temporary directories, exit-code assertions, command fakes, timeouts,
and machine-readable results. It must not silently turn live integration tests
into mocks.

The scripts now support `DOCKER_STUDENT_IDE_NONINTERACTIVE=1`. This suppresses
the success/failure pause and declines optional WSL installation instead of
waiting for input. A timeout remains a diagnostic guard, not a substitute for
fixing an automation-blocking script behavior.

The scripts are still procedural and perform native command, filesystem, and
process operations at load time. Pester tests must therefore begin with static
contracts and controlled child-process fixtures. Do not claim full unit
coverage until those side effects are extracted behind testable functions or
adapters.

## First Scenarios

The following scenarios are the initial acceptance set. They are deliberately
split between mocked tests and live tests so package installation is not part of
every pull request.

| ID | Layer | Scenario | Required evidence |
|---|---|---|---|
| I-01 | Pester | `install.ps1` finds Git and runs from an empty directory. | Clone target, working directory, child `powershell.exe` invocation, forwarded arguments, and final exit code. |
| I-02 | Pester plus live | The already-in-repository path does not clone again and invokes `start.ps1` with `-ExecutionPolicy Bypass`. | No clone call, exact child command shape, and argument preservation. |
| I-03 | Pester | Git is missing; the `winget` success, failure, and still-not-on-PATH branches are exercised. | Package-manager calls, refreshed PATH decision, actionable nonzero failure, and no infinite retry. |
| I-04 | Native Windows | A restricted execution policy is present while the documented one-liner or local install path is used. | The child bypass behavior, policy diagnostic, no secret leakage, and bounded completion. |
| S-01 | Pester | WSL is missing or unhealthy and the user declines installation. | No Docker installation attempt, actionable guidance, nonzero result, and no Compose invocation. |
| S-02 | Native Windows | WSL2 is healthy, Docker Desktop is installed, and the daemon is initially stopped. | Docker Desktop launch/wait behavior, readiness timeout, and a successful continuation after `docker info`. |
| S-03 | Pester | Docker CLI is absent, then package-manager installation succeeds or fails. | Correct installer fallback order, PATH refresh, exit code, and diagnostic classification. |
| S-04 | Pester | Docker CLI exists but the daemon never becomes ready. | Bounded polling, no unbounded sleep, final remediation text, and no `.env` or Compose mutation after failure. |
| S-05 | Pester plus live | `docker compose` v2 is missing or available. | Failure before startup in the missing case; Compose version check and forwarded `up` arguments in the available case. |
| S-06 | Pester | `.env` is absent, incomplete, or already correct. | `PUID=1000` and `PGID=1000`, preservation of unrelated values, no duplicate keys, and idempotence on a second run. |
| R-01 | Native Windows | A prepared Docker Desktop fixture runs `start.ps1 -d`. | Successful Compose startup, expected container state, and the configured browser-facing endpoint. |
| R-02 | External VM plus native Windows | The runtime starts, a marker is written to `student_workspace`, the stack is stopped and started again. | Container/runtime health and marker persistence without treating persistence as proof of Docker Desktop integration. |

### Native Windows (Docker-free) scenarios

The preferred Windows path (`setup-windows.ps1`) has its own scenario set. It
mirrors the Docker bootstrap but provisions Git, Node, Python, VS Code, and the
AI agents natively, so the Docker-specific premises (WSL, Docker Desktop, the
Compose daemon, `.env`) do not apply.

| ID | Layer | Scenario | Required evidence |
|---|---|---|---|
| N-01 | Contract | `setup-windows.ps1` and `requirements-windows.txt` exist; winget IDs, the Antigravity installer command, and the noninteractive seam are present; the script never invokes Docker or mutates `.env`. | Source assertions, no Docker command shapes, no `Update-EnvVar`. |
| N-02 | Pester | `winget` is missing. | Fail-fast with actionable guidance and nonzero result before any install. |
| N-03 | Pester | A pinned global npm tool is missing or already present. | Exact `npm install -g` command in the missing case; no `npm` call in the present case. |
| N-04 | Pester | Antigravity CLI install command shape. | Uses `irm https://antigravity.google/cli/install.ps1 | iex` and never the npm placeholder. |
| N-05 | Pester | VS Code user settings merge. | Creates the file, preserves existing keys, and stays idempotent. |
| N-06 | Pester | The VS Code extension harness. | The marketplace set includes pylance and docker (unavailable on code-server). |
| N-10 | Native Windows | A disposable Windows 11 fixture runs `setup-windows.ps1`. | Git, Node, Python, and VS Code are installed; the `.venv` and extension set are present. |
| N-11 | Native Windows | The native runtime is verified end-to-end. | Python stack imports, agent binaries respond, and VS Code opens the workspace. |

N-10/N-11 are pending until a disposable native-Windows fixture exists; pending
tests are not coverage claims.

The documented one-liner remains a separate networked contract test:

```powershell
irm https://raw.githubusercontent.com/CarlosAndres12/docker-student-ide/main/scripts/install.ps1 | iex
```

It should run only in a controlled disposable fixture, against an explicitly
selected revision or mirror. Deterministic tests should execute a staged copy
of the reviewed files instead of depending on the moving default branch.

## Test Construction

The bootstrap scripts now expose a minimal test seam without changing their
normal command-line behavior. Dot-sourcing either script loads its helpers
without running the bootstrap. `Wait-DockerDaemon` accepts retry and sleep
values, `Update-EnvVar` is independently callable, and the installer delegates
child PowerShell execution through `Invoke-ChildPowerShell`.

The test implementation is deliberately layered:

| Test file or support area | Use cases | Construction | Evidence |
|---|---|---|---|
| `tests/windows/unit/Bootstrap.Contracts.Tests.ps1` | Cross-cutting contracts | Read-only source assertions | Required command shapes and entry points |
| `tests/windows/unit/Bootstrap.Functions.Tests.ps1` | S-04, S-06, noninteractive behavior | Dot-source helpers with temporary files | Retry parameters, `.env` mutation, environment seam |
| `tests/windows/unit/Install.Tests.ps1` | I-01, I-02, I-03 | Controlled child process and command fakes | Clone calls, launcher arguments, package-manager branches, exit codes |
| `tests/windows/unit/Start.Tests.ps1` | S-01, S-03, S-04, S-05, S-06 | Mocked commands plus isolated temporary workspaces | No forbidden side effects, bounded probes, Compose arguments, idempotent `.env` |
| `tests/windows/integration/ExecutionPolicy.Tests.ps1` | I-04 | Disposable native Windows policy fixture | Bypass behavior, diagnostics, cleanup, and bounded completion |
| `tests/windows/integration/DockerDesktop.Tests.ps1` | S-02, R-01 | Prepared native Windows fixture | Docker Desktop launch, daemon readiness, Compose health, browser endpoint |
| `tests/windows/integration/RuntimePersistence.Tests.ps1` | R-02 | External snapshot and SSH adapter | Baseline identity, marker persistence, runtime health, restore result |

Each scenario must record its ID, fixture/baseline, revision, exit code,
stdout, stderr, duration, verdict, and failure class. Unit tests must use
temporary directories and fake commands. They must not install Git, WSL,
Docker Desktop, or packages.

### Use-case construction matrix

- **I-01**: start in an empty temporary directory; fake `git clone`; record the
  target and working directory; assert child PowerShell bypass, forwarded
  arguments, and exit code.
- **I-02**: provide `start.ps1` and `docker-compose.yml`; make any Git call a
  test failure; assert the child launcher is called directly with no clone.
- **I-03**: run three isolated cases for winget success, winget failure, and
  successful installation with Git still absent; assert one package-manager
  attempt and the corresponding diagnostic/exit code.
- **I-04**: use a pinned staged revision on disposable native Windows with a
  restricted policy; restore policy in teardown and redact secrets from
  captured output.
- **S-01**: fake missing/unhealthy WSL and select the noninteractive decline;
  assert no Docker installation or Compose invocation occurs.
- **S-02**: stop Docker Desktop in a prepared native fixture; assert launch,
  bounded readiness polling, and continuation after `docker info` succeeds.
- **S-03**: fake missing Docker CLI and exercise winget/choco fallback order,
  PATH refresh, diagnostics, and exit codes.
- **S-04**: make every `docker info` probe fail; pass small retry/sleep values;
  assert exact probe count, remediation output, and no `.env` or Compose write.
- **S-05**: fake missing and available Compose v2 separately; assert failure
  before mutation in the missing case and exact `up` argument forwarding in the
  available case.
- **S-06**: test absent, incomplete, correct, and repeated `.env` states;
  assert `PUID=1000`, `PGID=1000`, unrelated-key preservation, no duplicates,
  and second-run idempotence.
- **R-01**: run `start.ps1 -d` against the prepared native fixture; assert
  container state and the configured browser endpoint.
- **R-02**: restore a baseline, stage the reviewed revision through `Z:`, write
  a marker, stop/start the stack, and verify marker persistence separately from
  Docker Desktop integration claims.

Native and external-VM scenarios are represented by pending Pester tests until
their fixtures and adapters exist. Pending tests are not coverage claims.

## Running the Suite

The deterministic unit suite runs inside a PowerShell container so it can be
executed on any Docker-capable host, including Linux:

```bash
scripts/windows-testing/run-pester.sh
```

The runner builds `tests/windows/Dockerfile` (pwsh LTS with Pester 5),
mounts the repository read-only, and writes the JUnit result to a named volume
outside Git. Set `PESTER_RESULTS_PATH` to override the result location.

Evidence produced by the container proves that the PowerShell code parses and
the unit seams behave. It does **not** prove native Windows behavior.

The same suite runs on real Windows through the VM fixture:

```bash
scripts/windows-testing/vm-run.sh
```

This proves that the scripts parse and the unit seams behave under Windows
PowerShell 5.1 on Windows 11. It does **not** yet prove winget, WSL, Docker
Desktop, or reboot transitions; those still require the prepared-runtime
baseline (WSL2 and Docker Desktop, reachable through the fixture's VMX
exposure).

## Snapshot and Restore Lifecycle

The fixture is disposable state. The snapshot mechanism is implemented with an
immutable qcow2 base plus per-run disposable overlays, because the host
filesystem has no copy-on-write reflink support:

- The **base** (`/home/carlos/windows-snapshots/base/base.qcow2`, read-only)
  is a clean Windows 11 image with the SSH control plane, the runner key, and
  Pester 5.7.1 installed. It is never booted directly.
- Every run creates a **disposable overlay** (`data.qcow2` in the VM storage
  directory) whose backing file is the base. Only the run's delta is written,
  so disk usage per run is bounded by the guest changes, not a full copy.
- The protected post-OpenSSH master snapshot
  (`/home/carlos/windows-snapshots/20260813T071426Z-with-openssh`) remains the
  recovery point for the base chain and must never be modified or deleted.

| Baseline | Contents | Intended tests |
|---|---|---|
| `clean-bootstrap` | Implemented: the base image (Windows booted, SSH control plane, runner key, Pester 5.7.1, no test checkout). | Install, execution-policy, missing-prerequisite, and first-bootstrap scenarios. |
| `prepared-runtime` | WSL2 and Docker Desktop installed, daemon healthy, SSH available, and no test-owned Compose state. | `start.ps1`, Compose, runtime, and persistence scenarios. |

For each run (`scripts/windows-testing/vm-run.sh`):

1. Record the run ID, test revision, guest identity, and base identity.
2. Refuse to start if the VM container is still running; create the overlay only while the guest is fully stopped.
3. Boot from the overlay, then wait for the SSH port and guest health probe, not just the container process.
4. Stage the pinned revision through the `/shared` bind mount; the runner maps `Z:` inside the same SSH session (`net use Z: \\host.lan\Data`) and invokes the suite with `-NoProfile -NonInteractive -ExecutionPolicy Bypass`.
5. Collect results into the external results area (`/home/carlos/windows-vm/results/<run-id>/`).
6. Stop the VM gracefully and delete the overlay even after failure (keep it only with `--keep` for inspection).
7. Verify base integrity with the recorded SHA-256 before deleting any consolidated raw image or snapshot.

Host-side command shapes:

```bash
scripts/windows-testing/snapshot.sh create   # fresh disposable overlay
scripts/windows-testing/snapshot.sh list     # base + overlay state
scripts/windows-testing/vm-run.sh            # full run lifecycle
scripts/windows-testing/snapshot.sh delete   # discard the overlay
```

The baseline is selected with `WINDOWS_BASELINE` (default `clean-bootstrap`)
or `vm-run.sh --baseline <name>`. Both the `snapshot.sh` and `vm-run.sh`
adapters map `clean-bootstrap` to `base.qcow2` and `prepared-runtime` to
`prepared-runtime.qcow2` in the base directory; the disposable overlay keeps
the fixed `data.qcow2` name dockurr boots from, with its backing file pointing
at the selected baseline.

The adapter validates paths and VM state before it allows tests to continue.
Never start the VM storage directory without an overlay: dockurr would create
a new blank disk and reinstall Windows.

## SSH Orchestration

SSH is the control plane, not the behavior under test. The coordinator should:

- Keep the private key, known-hosts file, and any guest account details outside Git and CI logs.
- Bind and consume the current fixture through loopback: `127.0.0.1:2222`.
- Use `-o BatchMode=yes`, explicit connect and command timeouts, and a fixed host-key policy for the disposable fixture.
- Stage reviewed files into the VM's `/shared` bind source so the guest sees them under `Z:`.
- Invoke PowerShell with `-NoProfile -NonInteractive` and an explicit execution policy.
- Return the remote exit code unchanged while storing stdout and stderr separately.

Example command shapes:

```bash
ssh -p 2222 -o BatchMode=yes Docker@127.0.0.1 whoami
ssh -p 2222 -o BatchMode=yes Docker@127.0.0.1 powershell.exe \
  -NoProfile -NonInteractive -Command "Get-Service sshd | Select-Object Status,StartType"
ssh -p 2222 -o BatchMode=yes Docker@127.0.0.1 powershell.exe \
  -NoProfile -NonInteractive -ExecutionPolicy Bypass \
  -File Z:\windows-testing\run.ps1 -Scenario prepared-runtime
```

The future runner should use a unique `Z:\windows-testing\<run-id>` directory,
remove it after artifact collection, and never use the persistent `data.img` as
the result store. The current SSH verification proves transport and identity;
it does not prove that the test runner or any SUT scenario exists.

## Failure Diagnostics

Every scenario should emit a small result record containing scenario ID,
fixture/baseline, test revision, start/end time, exit code, verdict, and failure
class (`sut`, `assertion`, `ssh`, `snapshot`, `timeout`, or `environment`).

On failure, collect as applicable:

- Full PowerShell and child-process stdout/stderr with timestamps.
- The exact command shape and argument list, with passwords, tokens, and authorization headers redacted.
- `wsl --status`, `docker version`, `docker info`, and `docker compose ps` from the guest.
- Compose logs and container state for runtime scenarios.
- Disk/image state, VM lifecycle events, and SSH connection diagnostics for infrastructure failures.
- A final guest health probe and whether cleanup/restore completed.

Do not classify a timeout as a product failure until SSH, VM state, and the
guest command process have been checked. Preserve diagnostics outside the repo
under the external VM's controlled results area or as protected CI artifacts;
never commit `data.img`, guest profiles, private keys, or raw environment files.

## CI Evolution

There is currently no `.github` workflow or Windows runner. Evolve CI in this
order:

1. **Static gate:** run shell syntax checks, repository contract checks, and `docker compose config` on Linux. Add PowerShell parsing only when a PowerShell engine is available; label it accurately.
2. **Mocked Windows gate:** add a `windows-latest` job for Pester/unit tests that do not install Docker Desktop or depend on privileged host state. A future command shape is:

   ```powershell
   Invoke-Pester -Path .\tests\windows -CI
   ```

3. **Native integration gate:** use a dedicated, protected Windows runner with WSL2 and Docker Desktop preinstalled. Do not assume a hosted Windows runner provides the required Docker Desktop mode, nested virtualization, snapshots, or reboot control.
4. **External VM proof:** run the dockur/windows scenarios manually first, then on a scheduled or protected-branch job after snapshot/restore and cleanup are reliable. Keep this job non-blocking until its infrastructure failure rate is understood.
5. **Maintenance matrix:** record Windows version, PowerShell version, WSL version, Docker Desktop version, Compose version, and fixture baseline for each run.

Untrusted pull requests must not receive access to a self-hosted Windows
runner, the SSH key, the VM, or a Docker-capable host. CI examples must use
protected variables only where a real secret is required; this plan requires no
secret values in source or example commands.

## Security Boundaries

- Treat `irm | iex` as networked code execution. Pin the revision for tests, use TLS, and make the downloaded source visible in diagnostics without logging secrets.
- Keep SSH credentials, `known_hosts`, Docker credentials, and any test password outside the repository. Use an ephemeral test value supplied by the fixture or CI secret store.
- Keep SSH bound to loopback for the current VM. Do not widen the port exposure merely to simplify orchestration.
- Use a dedicated disposable guest account and document its privileges. Do not assume the current `Docker` identity is least-privileged.
- Restrict fixture network egress to what installation and image pulls need. Never run untrusted pull-request code against a persistent workstation or shared Docker socket.
- Treat `/shared` as a test transfer boundary. Do not copy host credentials, personal files, or the full host filesystem into it.
- Protect `data.img` and snapshots with host filesystem permissions and retention rules. A snapshot can contain machine state and must not become a repository artifact.

## Phased Implementation Backlog

### Phase 0: Contracts and observability

- [x] Define the initial test tree, scenario IDs, timeouts, artifact retention, and failure classes.
- [x] Add static Pester contracts for bootstrap entry points and required command shapes.
- [x] Define noninteractive behavior for `Exit-WithPause` before remote automation is enabled.
- [x] Add machine-readable result output and classify infrastructure failures separately from SUT failures (`result.json` verdict/failure-class plus `scenarios.json` per-scenario summary in the VM runner).

**Exit condition:** static checks fail deterministically and distinguish missing
tooling from a failed SUT assertion.

### Phase 1: Isolated PowerShell tests

- [x] Create the Windows test tree and Pester configuration.
- [x] Add disposable workspace, command-fake, and child-process scenario helpers.
- [x] Add per-use-case unit and native/VM test skeletons with explicit tags.
- [x] Extract side-effecting bootstrap operations behind testable functions or adapters (child-process drivers, PATH fakes, function shadows; the bootstrap scripts themselves needed only the argument-forwarding and exit-code fixes).
- [x] Add mocks and tests for install cloning, execution-policy bypass, package-manager fallback, WSL branches, Docker readiness, Compose detection, `.env` idempotence, and argument forwarding.
- [x] Add bounded waits and output redaction assertions (S-04 probe bounds, I-04 no-secret check).

**Exit condition:** all I-01 through I-03 and S-01 through S-06 run without
installing software or mutating a real Windows machine. I-03's
clone-continuation case runs on Linux hosts and is skipped on Windows
hosts because the bootstrap rebuilds PATH from the registry; live winget
coverage belongs to the disposable-VM layer.

### Phase 2: VM control and recovery

- [x] Implement snapshot create/list/restore around the external qcow2 base (`scripts/windows-testing/snapshot.sh`).
- [x] Implement SSH preflight, staging through `Z:`, remote execution, timeout handling, and cleanup (`scripts/windows-testing/vm-run.sh`).
- [x] Create and verify the `clean-bootstrap` baseline (immutable base with SSH control plane and Pester 5.7.1).
- [ ] Create and verify the `prepared-runtime` baseline (WSL2 + Docker Desktop).

**Exit condition:** a deliberately failing scenario still restores a usable
baseline and produces classified diagnostics.

### Phase 3: Native Windows integration

- [x] Run I-04 against a real restricted execution policy on the VM fixture (negative control proves the stub is blocked; the positive proves the child bypass seam executes it).
- [ ] Prepare a disposable Windows 11 fixture with WSL2 and Docker Desktop.
- [ ] Run S-02, S-05, and R-01/R-02 against real platform dependencies.
- [ ] Include reboot and first-run state transitions where the bootstrap scripts require them.

**Exit condition:** the suite proves native Windows + WSL2 + Docker Desktop,
not only PowerShell syntax or the external VM's guest runtime.

### Phase 4: CI and ongoing maintenance

- [x] Add the mocked `windows-latest` job and Linux static gate (`.github/workflows/ci.yml`).
- [ ] Add a protected self-hosted integration job only after its isolation and cleanup controls are reviewed.
- [ ] Add scheduled external-VM runtime proof with baseline versioning and artifact retention.
- [ ] Review the matrix when Windows, WSL2, Docker Desktop, Compose, or bootstrap behavior changes.

**Exit condition:** every required layer has an owner, a repeatable fixture,
actionable failure evidence, and a documented reason for its CI cadence.
