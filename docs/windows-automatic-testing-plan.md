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
| External fixture | A live `dockur/windows` VM exists at `/home/carlos/windows-vm`. It runs Windows 11 with 8 GB RAM, 4 vCPU, and a persistent `data.img`. | Use it for controlled runtime proof, not as an implicit repository dependency. |
| VM control plane | The host `/shared` bind mount appears as `Z:` in Windows. OpenSSH is installed and verified: `sshd` is Running with Automatic startup, the `OpenSSH-Server-In-TCP` firewall rule exists, and the guest listens on `:::22`. | The host can stage files and run noninteractive guest commands over SSH. |
| SSH proof | `ssh -p 2222 Docker@127.0.0.1 whoami` returns the Windows identity. | SSH orchestration is viable, but credentials and the SSH key must stay outside the repository. |

### Current implementation boundary

The current uncommitted change set under review includes the Windows bootstrap
scripts, their shell counterparts, Docker image cleanup, deployment
documentation, and this testing plan. The tracked testing implementation lives
under `tests/windows/`; host-side VM adapters will live under
`scripts/windows-testing/` when Phase 2 starts. No test source is authoritative
inside `/home/carlos/windows-vm`.

The following evidence is currently valid:

- Linux static checks: shell syntax and `docker compose config`.
- External VM checks: SSH transport, guest identity, OpenSSH service state, and
  shared-directory staging.
- Pester contract tests: source-level bootstrap invariants, when executed on a
  Windows host with Pester 5.

The following evidence is not yet available:

- PowerShell execution on the host used for development.
- Native Windows + WSL2 + Docker Desktop integration.
- Snapshot/restore orchestration implemented in the repository.
- A Windows CI runner or scheduled external-VM job.

The external VM snapshot, credentials, image, and result artifacts remain
outside Git. The VM must not be treated as a substitute for native Windows
coverage.

The VM is useful for runtime proof, guest command orchestration, and diagnostics.
It does **not** replace coverage on native Windows with WSL2 and Docker Desktop.
Those layers exercise the platform dependencies that the current `dockur/windows`
fixture does not prove by itself and must be covered separately.

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
the unit seams behave. It does **not** prove native Windows behavior: winget,
WSL, Docker Desktop, execution policy, and reboot transitions still require a
native Windows fixture.

## Snapshot and Restore Lifecycle

The fixture must be treated as disposable state. At minimum, define two
versioned baselines outside Git:

| Baseline | Contents | Intended tests |
|---|---|---|
| `clean-bootstrap` | Windows booted, SSH control plane configured, no test checkout or test workspace, and no untracked SUT state. | Install, execution-policy, missing-prerequisite, and first-bootstrap scenarios. |
| `prepared-runtime` | WSL2 and Docker Desktop installed, daemon healthy, SSH available, and no test-owned Compose state. | `start.ps1`, Compose, runtime, and persistence scenarios. |

For each run:

1. Record the baseline ID, test revision, guest identity, and run ID.
2. Stop the guest and all test-owned workloads before creating or restoring an image.
3. Restore the selected `data.img` baseline before the scenario; never reuse a mutated guest silently.
4. Start the VM and wait for the SSH port and guest health probe, not just the container process.
5. Stage the test revision through the `/shared` bind mount and invoke the guest runner from `Z:`.
6. Collect results and diagnostics, then stop the VM and restore the baseline even after failure.
7. Verify that the restored image is usable before marking infrastructure recovery successful.

The exact snapshot mechanism is an implementation task. It may be a storage
snapshot or a sparse, verified image copy. The invariant is that `data.img` is
never replaced while the VM is running and that snapshots remain outside the
repository. Illustrative host-side command shapes are:

```bash
docker compose -f /home/carlos/windows-vm/docker-compose.yml down
# Create or restore a versioned snapshot while the guest is fully stopped.
cp --reflink=auto /home/carlos/windows-vm/snapshots/<baseline>/data.img \
  /home/carlos/windows-vm/data.img
docker compose -f /home/carlos/windows-vm/docker-compose.yml up -d
```

These are command shapes for the future adapter, not commands to run as part
of this document change. The adapter must validate paths, VM state, image size,
and restore completion before it allows tests to continue.

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
- [ ] Add machine-readable result output and classify infrastructure failures separately from SUT failures.

**Exit condition:** static checks fail deterministically and distinguish missing
tooling from a failed SUT assertion.

### Phase 1: Isolated PowerShell tests

- [x] Create the Windows test tree and Pester configuration.
- [x] Add disposable workspace, command-fake, and child-process scenario helpers.
- [x] Add per-use-case unit and native/VM test skeletons with explicit tags.
- [ ] Extract side-effecting bootstrap operations behind testable functions or adapters.
- [ ] Add mocks and tests for install cloning, execution-policy bypass, package-manager fallback, WSL branches, Docker readiness, Compose detection, `.env` idempotence, and argument forwarding.
- [ ] Add bounded waits and output redaction assertions.

**Exit condition:** all I-01 through I-03 and S-01 through S-06 run without
installing software or mutating a real Windows machine.

### Phase 2: VM control and recovery

- [ ] Implement snapshot create/list/restore around the external `data.img`.
- [ ] Implement SSH preflight, staging through `Z:`, remote execution, timeout handling, and cleanup.
- [ ] Create and verify `clean-bootstrap` and `prepared-runtime` baselines.

**Exit condition:** a deliberately failing scenario still restores a usable
baseline and produces classified diagnostics.

### Phase 3: Native Windows integration

- [ ] Prepare a disposable Windows 11 fixture with WSL2 and Docker Desktop.
- [ ] Run I-04, S-02, S-05, and R-01/R-02 against real platform dependencies.
- [ ] Include reboot and first-run state transitions where the bootstrap scripts require them.

**Exit condition:** the suite proves native Windows + WSL2 + Docker Desktop,
not only PowerShell syntax or the external VM's guest runtime.

### Phase 4: CI and ongoing maintenance

- [ ] Add the mocked `windows-latest` job and Linux static gate.
- [ ] Add a protected self-hosted integration job only after its isolation and cleanup controls are reviewed.
- [ ] Add scheduled external-VM runtime proof with baseline versioning and artifact retention.
- [ ] Review the matrix when Windows, WSL2, Docker Desktop, Compose, or bootstrap behavior changes.

**Exit condition:** every required layer has an owner, a repeatable fixture,
actionable failure evidence, and a documented reason for its CI cadence.
