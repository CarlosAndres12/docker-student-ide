# Windows Native Setup (Docker-free)

`setup-windows.ps1` is the preferred Windows path. It provisions the full
docker-student-ide environment **natively** on Windows — no Docker, no WSL2,
no code-server — while keeping parity with what the Docker image provides.

`start.ps1` remains the Docker path and is unchanged.

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
2. **Git** — `winget Git.Git`.
3. **Node.js LTS** — `winget OpenJS.NodeJS.LTS`.
4. **Python** — `winget Python.Python.3.13`, then a `.venv` with the CPU
   PyTorch wheels and `requirements-windows.txt`.
5. **Global npm tools** — `create-vite@5.1.0`, `typescript@5.6.2`,
   `npm-check-updates@17.1.3` (pinned, same as the Dockerfile).
6. **AI agents** — Pi, OpenCode, Freebuff, pi-free, engram, gentle-ai, Qoder,
   Antigravity CLI.
7. **VS Code** — `winget Microsoft.VisualStudioCode` + 16 extensions + terminal
   keybinding settings.
8. **Pi free-only** — `PI_FREE_ONLY=1` (user env) + `~/.pi/free.json`.
9. **Launch** VS Code on `student_workspace/`.
10. **Verification** — version report for every installed tool.

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
- **`irm ... | iex`** is used only for the two official installers (Qoder,
  Antigravity), matching each vendor's documented command.

## Verification

The deterministic unit suite (`tests/windows/unit/Native.Tests.ps1`, scenarios
N-02..N-06 plus the "Native Windows setup contracts" block) runs under pwsh on
Linux via `scripts/windows-testing/run-pester.sh`. Native provisioning itself
is a disposable-Windows integration concern (`N-10`/`N-11`, pending).
