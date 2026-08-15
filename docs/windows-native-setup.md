# Windows Native Setup (Docker-free)

`setup-windows.ps1` is the preferred Windows path. It provisions the full
docker-student-ide environment **natively** on Windows — no Docker, no WSL2,
no code-server — while keeping parity with what the Docker image provides.

`start.ps1` remains the Docker path and is unchanged.

## One-liner bootstrap

The student-facing entry point is a single command, run from the folder where
the workspace should live:

```powershell
irm https://raw.githubusercontent.com/CarlosAndres12/docker-student-ide/main/scripts/install-native.ps1 | iex
```

`scripts/install-native.ps1` is the bootstrap. It is **Git-free and
policy-free**:

- Runs in-memory via `irm | iex`, so a `Restricted` execution policy cannot
  block it and no `.ps1` file is saved.
- Forces TLS 1.2 (PowerShell 5.1 on older Windows 10).
- Downloads the repository as a **ZIP**
  (`.../archive/refs/heads/main.zip`) instead of `git clone`, so Git is not
  required to start.
- Extracts to `./docker-student-ide` and runs `setup-windows.ps1` in a child
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File` process (child-scoped
  bypass).
- Is idempotent: if `setup-windows.ps1` is already present it skips the download.

Git is installed later by `setup-windows.ps1` itself (step 2 below), before
anything that depends on it (pi-free uses `git clone`).

## Runtime model

| Concern | Docker container | Native Windows |
|---|---|---|
| IDE | code-server in a browser (`:8443`) | VS Code Desktop (Microsoft Store/MSI) |
| Extensions | Open VSX (14) | VS Code Marketplace (16, incl. pylance + docker) |
| Node.js | 22.23.1 (pinned tarball) | LTS via winget (latest) |
| Python | 3.11 + `/opt/venv` | latest (3.13) + repo-local `.venv` |
| ML/DL stack | `requirements.txt` (3.11 pins) | `requirements-windows.txt` (3.13 pins) |
| AI agents | Pi, OpenCode, Freebuff, gentle-ai, Qoder | same + Antigravity CLI (`agy`) |
| Workspace | bind-mount `student_workspace` | VS Code opens `student_workspace/` |
| `.env` / PUID / PGID | used | not applicable (no container) |

## Provisioning order

1. **Gate** — winget presence + elevation guidance.
2. **Git** — `winget Git.Git` (installed first so pi-free and other
   git-dependent packages work).
3. **Node.js LTS (≥ 22)** — `Get-NodeMajorVersion` gates on major ≥ 22;
   otherwise `winget OpenJS.NodeJS.LTS` and re-check.
4. **Python (≥ 3.13)** — `Resolve-PythonLauncher` prefers `py -3.13`, then
   `python --version ≥ 3.13`; otherwise `winget Python.Python.3.13`. The venv
   is created with the resolved launcher so a stale `python` on PATH cannot
   leak in.
5. **`.venv` + ML/DL stack** — CPU PyTorch wheels then `requirements-windows.txt`.
6. **Global npm tools** — `create-vite@5.1.0`, `typescript@5.6.2`,
   `npm-check-updates@17.1.3` (pinned, same as the Dockerfile).
7. **AI agents** — Pi, OpenCode, Freebuff, pi-free, engram, gentle-ai, Qoder,
   Antigravity CLI.
8. **VS Code** — `winget Microsoft.VisualStudioCode` + 16 extensions + terminal
   keybinding settings.
9. **Pi free-only** — `PI_FREE_ONLY=1` (user env) + `~/.pi/free.json`.
10. **Launch** VS Code on `student_workspace/`.
11. **Verification** — version report for every installed tool.

The core toolchain (Git, Node, Python, VS Code) fails hard on error; agent
installs are best-effort and only warn. Everything is idempotent.

## Version matrix

Versions installed by `winget` are the latest available and are not pinned;
the rest are pinned for reproducibility. Record the resolved winget versions
here after a fresh provision (the script prints them at the end of each run).

| Tool | Source | Pin |
|---|---|---|
| Git | winget `Git.Git` | latest |
| Node.js | winget `OpenJS.NodeJS.LTS` | latest |
| Python | winget `Python.Python.3.13` | 3.13 |
| VS Code | winget `Microsoft.VisualStudioCode` | latest |
| create-vite | npm | 5.1.0 |
| typescript | npm | 5.6.2 |
| npm-check-updates | npm | 17.1.3 |
| pi | npm `@earendil-works/pi-coding-agent` | latest |
| opencode | npm `opencode-ai` | latest |
| freebuff | npm `freebuff` | latest |
| pi-free | git clone `apmantza/pi-free` | commit `6119a18` |
| engram | GitHub release | 1.19.0 |
| gentle-ai | GitHub release | 2.1.10 |
| qodercli | qoder.com/install | latest |
| agy (Antigravity) | antigravity.google/cli/install.ps1 | latest |

## Key decisions and gotchas

- **Version gating, not just presence.** `Get-NodeMajorVersion` (≥ 22, required
  by pi-coding-agent) and `Resolve-PythonLauncher` (≥ 3.13) guard against a
  stale Node/Python already on the student PC. The Python venv is created with
  `py -3.13` when available, so an old `python` on PATH cannot leak in.
- **Python is latest (3.13), not 3.11.** The Docker image stays on 3.11 with
  `requirements.txt`; several 2024-era pins there have no cp313 wheels, so the
  native path uses `requirements-windows.txt`. Do not merge the two files.
- **torch/torchvision** are installed first from the CPU wheel index
  (`https://download.pytorch.org/whl/cpu`) exactly as in the Dockerfile, then
  `requirements-windows.txt` installs the rest (pip skips the satisfied pins).
- **No CUDA strip is needed on Windows** — `xgboost`'s `nvidia-nccl-cu12`
  hard dependency is Linux-only.
- **Antigravity CLI is `agy`, not an npm package.** The npm package
  `antigravity-cli` (and `antigravity`) are placeholders. Install via
  `irm https://antigravity.google/cli/install.ps1 | iex`. Same trap as the
  `pi` joke package.
- **Pi default CLI**: `npm install -g pi` is a joke package that prints "3";
  the real CLI is `@earendil-works/pi-coding-agent` (provides `pi`).
- **Go binaries** (engram, gentle-ai) ship `windows_amd64.zip` archives whose
  contents are `engram.exe` / `gentle-ai.exe`; they are extracted into
  `%LOCALAPPDATA%\docker-student-ide\bin` and that directory is added to the
  User `PATH` persistently.
- **`irm ... | iex`** is used only for the official installers (Qoder,
  Antigravity, and the bootstrap), matching each vendor's documented command.

## Verification

The deterministic unit suite runs under pwsh on Linux via
`scripts/windows-testing/run-pester.sh`:

- `tests/windows/unit/InstallNative.Tests.ps1` — NI-01..NI-03 (ZIP download →
  child bypass, already-in-repo, download failure).
- `tests/windows/unit/Native.Tests.ps1` — N-02..N-07 (winget gate, npm installs,
  Antigravity, settings merge, extension harness, version gating).
- `tests/windows/unit/Bootstrap.Contracts.Tests.ps1` — native setup and
  installer contracts.

Native provisioning itself is a disposable-Windows integration concern
(`N-10`/`N-11`, pending).
