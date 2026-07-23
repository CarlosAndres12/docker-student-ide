# docker-student-ide — Deployment Guide

A browser-based IDE with Node 22, Python 3.11 ML/DL stack, Jupyter, MLflow,
and the Pi AI assistant — all behind a single `docker compose up`.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Pinned Versions](#2-pinned-versions)
3. [Build & Run](#3-build--run)
4. [First Login](#4-first-login)
5. [Per-Course Usage Notes](#5-per-course-usage-notes)
6. [Subsystem Verification](#6-subsystem-verification)
7. [Pi AI Assistant Configuration](#7-pi-ai-assistant-configuration)
8. [Reverse Proxy / TLS (for non-localhost use)](#8-reverse-proxy--tls-for-non-localhost-use)
9. [Build Time & Image Size](#9-build-time--image-size)
10. [Troubleshooting](#10-troubleshooting)
11. [Alternative AI Agents](#11-alternative-ai-agents)

---

## 1. Prerequisites

| Requirement | Notes |
|---|---|
| **NVIDIA Container Toolkit** | **Optional** — only needed for GPU passthrough. Install from [docs.nvidia.com](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/) |
| **Internet connection** | First build downloads ~4–6 GB of packages |
| **~20 GB free disk** | Build cache + final image + workspace |

> **🚀 Docker & Docker Compose are auto-installed by the bootstrap scripts.**
> - **macOS / Linux**: `./start.sh` — installs Docker (via Homebrew or apt/dnf/pacman) and Compose v2 if missing.
> - **Windows**: `.\start.ps1` (PowerShell) — installs Docker Desktop via winget or Chocolatey.
>
> If you prefer to install Docker manually, see [docs.docker.com/engine/install/](https://docs.docker.com/engine/install/).
> Docker Desktop includes Compose v2; on Linux you need the `docker-compose-plugin` package.

---

## 2. Pinned Versions

Everything is pinned for reproducibility.  Before rebuilding, check for newer
stable releases and update these values across **all** files:

| Component | Pinned Version | Location |
|---|---|---|
| Base image (code-server) | `lscr.io/linuxserver/code-server:4.93.1` | `Dockerfile` (both stages) |
| Node.js | 22.23.1 (LTS "Jod") | `Dockerfile` (deps stage) |
| Python | 3.11.9 | `Dockerfile` (deps stage via deadsnakes PPA) |
| pi-free (GitHub) | Commit `6119a187afa8f444376026836b60649cac3d3621` | `Dockerfile` (deps stage) |
| All Python packages | See `requirements.txt` (every line pinned with `==`) | `requirements.txt` |
| Starter frontend deps | See `package.json` (every dep pinned) | `package.json` |
| Global npm CLI tools | `create-vite@5.1.0`, `typescript@5.6.2`, `npm-check-updates@17.1.3` | `Dockerfile` (deps stage) |
| opencode-ai (npm global) | `opencode-ai@latest` | `Dockerfile` (deps stage) |
| freebuff (npm global) | `freebuff@latest` | `Dockerfile` (deps stage) |
| gentle-ai (Go binary) | `gentle-ai v2.1.10` | `Dockerfile` (deps stage) |
| MiMo (precompiled binary) | Installed via `curl -fsSL https://mimo.xiaomi.com/install \| bash` (not pinned; installer fetches latest) | `Dockerfile` (deps stage) |
| Qoder CLI (precompiled binary) | Installed via `curl -fsSL https://qoder.com/install \| bash` (not pinned; installer fetches latest from CDN manifest) | `Dockerfile` (deps stage) |

> npm packages use `@latest`; resolved versions are recorded at build time in the Dockerfile.
> 
> **pi-free commit maintenance**: The pinned SHA is set at build time.  If
> pi-free's repository changes layout or the install path changes, check
> [pi.dev/packages/pi-free](https://pi.dev/packages/pi-free) for the current
> install command.  See §7.3 for details.

---

## 3. Build & Run

**Zero-config startup — no manual file editing required. Docker is auto-installed if missing.**

### 3.1 Choose your platform

| Platform | Command |
|---|---|
| **macOS** / **Linux** | `./start.sh` |
| **Windows (PowerShell)** | `.\start.ps1` |

Both scripts:
- Install Docker if not already present (Docker Desktop on macOS/Windows; `docker.io` on Linux via apt/dnf/pacman).
- Wait for the Docker daemon to start.
- Auto-detect PUID/PGID (Unix) or set safe defaults (Windows) and write them into `.env`.
- Forward all arguments to `docker compose up`.

To run in the background:

```bash
./start.sh -d       # macOS / Linux
.\start.ps1 -d      # Windows (PowerShell)
```

If you prefer not to use a wrapper script, `docker compose up` also works
with no prior configuration — the compose file provides inline defaults for
every variable.

### 3.2 First build

The first time you run either command, Docker builds the image automatically.

**First build:** 10–20 minutes (see §9 for details).  Subsequent rebuilds are
much faster thanks to Docker layer caching.

### 3.3 Stop the container

```bash
docker compose down
```

### 3.4 View logs

```bash
docker compose logs -f
```

### 3.5 Optional overrides (advanced)

The shipped `.env` file is ready to run as-is.  If you need custom values,
edit `.env` directly — all changes are optional:

```bash
# Change the code-server password (recommended on shared machines)
PASSWORD=student

# Override ports when defaults are in use
CODESERVER_PORT=9443     # instead of 8443
JUPYTER_PORT=8889        # instead of 8888
MLFLOW_PORT=5556         # instead of 5555

# Override PUID/PGID (start.sh detects these automatically; only needed
# when using docker compose up directly and your IDs are not 1000)
PUID=1000
PGID=1000
```

After editing `.env`, restart the container:

```bash
docker compose down
docker compose up -d
```

> For a full list of every configurable variable, see the reference template
> at `.env.example` (not required reading — documentation only).

---

## 4. First Login

1. Open your browser to **http://localhost:8443** (or the port set in
   `CODESERVER_PORT` in `.env`).

2. Enter the default password: **`student`** (as set in the shipped `.env`).
   If you changed `PASSWORD` in `.env`, use that value instead.

3. code-server opens to `/config/workspace` — this is your `student_workspace/`
   directory on the host.  Everything you create here persists across restarts.

4. Open a terminal inside code-server (**Terminal → New Terminal**) and verify
   the stack (see §6).

> **⚠️ Change the password on shared machines.**  Edit `PASSWORD` in `.env`
> and restart the container.  See §3.5 for instructions.

---

## 5. Per-Course Usage Notes

### Web-Development Course

| Tool / Port | How to reach it |
|---|---|
| code-server IDE | http://localhost:8443 |
| Frontend dev servers (3000–9999) | Start your dev server (e.g. `npm run dev`), then click the **Ports** tab in code-server's sidebar and forward the port. No host mapping needed. |
| Starter `package.json` | Copy `student_workspace/package.json` or the repo-root `package.json` into your project folder, then run `npm install`. |
| Node / npm | `node -v` → `v22.23.1`, `npm -v` (available globally) |
| `VITE_API_BASE_URL` | If your frontend calls `https://astryx.atmeta.com/`, set this env var in your project's `.env` file. **This is student-side config — nothing is baked into the Docker image.** You will need to configure CORS on the API side as well. |

**To scaffold a new Vite project:**

```bash
npm create vite@latest my-app -- --template react
cd my-app
npm install
npm run dev
```

Then forward port 5173 (or whatever Vite prints) via code-server's Ports tab.

### Machine Learning / Data-Science Course

| Tool / Port | How to reach it |
|---|---|
| code-server IDE | http://localhost:8443 |
| Jupyter / JupyterLab | http://localhost:8888 |
| MLflow UI | http://localhost:5555 |
| Python ML/DL stack | Everything pre-installed in `/opt/venv` (pandas, numpy, scipy, scikit-learn, PyTorch CPU, TensorFlow CPU, xgboost, lightgbm, transformers, opencv, etc.) |

**Start JupyterLab:**

```bash
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root
```

(Or use the shortcut `jupyter notebook` for the classic interface.)

**Start MLflow:**

```bash
mlflow ui --host 0.0.0.0 --port 5555
```

### General CS / Combined Courses

You have everything from both stacks above.  Use code-server for code editing,
Jupyter for notebooks, and MLflow for experiment tracking — all from the same
container.

---

## 6. Subsystem Verification

Run these commands inside the code-server terminal to verify each component.

### Node.js

```bash
node -v
# Expected: v22.23.1
npm -v
# Expected: a valid npm version
```

### Global CLI Tools

```bash
create-vite --help       # should print usage
tsc --version            # should print 5.6.2
npm-check-updates        # should print help/version
```

### Python & ML/DL Stack

```bash
python --version
# Expected: Python 3.11.x

python -c "import pandas; import numpy; import scipy; import sklearn; print('Core stack OK')"
python -c "import torch; import torchvision; print('PyTorch', torch.__version__)"
python -c "import tensorflow as tf; print('TensorFlow', tf.__version__)"
python -c "import xgboost; import lightgbm; print('Boosting stack OK')"
python -c "import transformers; import cv2; import nltk; print('NLP/CV stack OK')"
python -c "import matplotlib; import seaborn; import plotly; print('Viz stack OK')"
python -c "import optuna; import mlflow; print('Experiment tools OK')"
```

### Jupyter

```bash
jupyter --version
```

Then open http://localhost:8888 in your browser.  You should see JupyterLab.

### MLflow

Start MLflow:

```bash
mlflow ui --host 0.0.0.0 --port 5555 &
```

Then open http://localhost:5555 in your browser.  You should see the MLflow UI.

### Pi AI Assistant

```bash
pi --version
# Should print a version number

pi package list
# Should show: gentle-pi, gentle-engram, pi-free
```

### Alternative AI Agents

```bash
opencode --version
# Expected: a version number (e.g. x.y.z)

freebuff --version
# Expected: a version number (e.g. x.y.z)

gentle-ai --version
# Expected: v2.1.10

mimo --version
# Expected: a version number (e.g. x.y.z)

qodercli --version
# Expected: a version number (e.g. x.y.z)
```

### GPU (if enabled)

```bash
nvidia-smi
# Expected: a table listing your NVIDIA GPU(s) and driver version
```

If `nvidia-smi` is not found, verify:
- `DEVICE=gpu` is set in `.env`
- The `deploy:` block in `docker-compose.yml` is uncommented
- The NVIDIA Container Toolkit is installed on the host

---

## 7. Pi AI Assistant Configuration

### 7.1 Free-Tier Routing

Pi is locked to free/zero-cost providers by default via two mechanisms:

1. **Environment variable** (`PI_FREE_ONLY=1`) — enforced at container start.
2. **Config file** at `/home/abc/.pi/config.json` — contains `{"free":true}`.

You can inspect the current tier with:

```bash
pi-free status     # shows current routing mode
```

To toggle between free-only and all providers:

```bash
pi-free free       # lock to free/zero-cost providers only
pi-free all        # allow all (including paid) providers
```

### 7.2 pi-free Provenance & Maintenance Risk

**Important:** `pi-free` is installed directly from a GitHub repository
(`github.com/apmantza/pi-free`) pinned to a specific commit SHA.  Unlike
`gentle-pi` and `gentle-engram` (which come from the npm registry with
provenance guarantees), pi-free:

- Has **no npm registry provenance**.
- Is a **GitHub repo that could change or disappear**.
- Is **pinned to a commit** at build time (`6119a187afa8f444376026836b60649cac3d3621`).

**If the install path changes** in a future version of pi-free, check
[pi.dev/packages/pi-free](https://pi.dev/packages/pi-free) for the current
install command and update the Dockerfile accordingly.

### 7.3 OAuth-in-Headless-Container Workarounds

Some Pi free-tier providers (notably `kilo`, `cline`) use browser-based OAuth
flows.  These do **not** work inside a headless container by default.  Two
workarounds exist:

#### (a) Key-based auth via environment variables

Providers that support API-key authentication can be configured before
container start by uncommenting the relevant lines in `.env`:

```bash
KILO_API_KEY=your_kilo_key_here
CLINE_API_KEY=your_cline_key_here
OPENROUTER_API_KEY=your_openrouter_key_here
```

These are written to `~/.pi/free.json` or exported as environment variables
that the Pi CLI reads at startup.

#### (b) One-time port-forwarded browser OAuth flow

For OAuth-only providers:

1. Start the container and open code-server in your browser.
2. Open a terminal in code-server and run `pi login <provider>` (e.g. `pi login kilo`).
3. code-server's port-forwarding can expose the OAuth callback if needed.
   The OAuth flow opens a URL — copy it and paste it into your host browser.
4. Complete the browser OAuth flow on your host.
5. The resulting token is persisted in the bind-mounted workspace (at
   `student_workspace/.pi/` or wherever the provider writes its token), so it
   **survives container restarts**.

> **Tip**: After completing the OAuth flow once, your session stays
> authenticated across `docker compose down` / `docker compose up` cycles as
> long as the token file lives inside `student_workspace/`.

---

## 8. Reverse Proxy / TLS (for non-localhost use)

**Not enabled by default.**  The stack is designed for localhost-only use out of
the box.  If you need to access code-server from another machine or over the
internet, insert a reverse proxy (nginx, Caddy, Traefik) in front of the
container.

Suggested insertion point in `docker-compose.yml`:

```yaml
services:
  reverse-proxy:
    image: nginx:alpine
    ports:
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - code-server
```

The reverse proxy would:

- Terminate TLS (Let's Encrypt / certbot).
- Proxy `/` to `http://code-server:8443`.
- Optionally proxy `/jupyter` to `http://code-server:8888` and `/mlflow` to
  `http://code-server:5555`.

See the [linuxserver/code-server reverse proxy docs](https://docs.linuxserver.io/images/docker-code-server/#reverse-proxy)
for example nginx/Apache configs.

> **Security note**: Never expose code-server directly to the internet without
> TLS.  The `PASSWORD` env var is transmitted in cleartext over HTTP.

---

## 9. Build Time & Image Size

| Metric | Expected Value |
|---|---|
| **First build time** | 10–20 minutes (depends on network speed and CPU) |
| **Subsequent rebuilds** | 1–5 minutes (cached layers) |
| **Final image size (CPU-only)** | 4–6 GB |
| **Final image size (GPU variant)** | 6–8 GB (includes CUDA libraries) |

The multi-stage Dockerfile keeps the final image lean by excluding build
toolchains, wheel caches, and `node_modules/.cache` from the runtime stage.

---

## 10. Troubleshooting

### Port Conflicts

**Symptom**: `docker compose up` fails with `port is already allocated`.

**Detection**: Find what is using the port on your host:

```bash
ss -tlnp | grep -E ':(8443|8888|5555) '
```

Or use the older `netstat`:

```bash
netstat -tulpn | grep -E ':(8443|8888|5555) '
```

**Fix**: Override the conflicting port in `.env`:

```bash
# .env
CODESERVER_PORT=9443     # instead of 8443
JUPYTER_PORT=8889        # instead of 8888
MLFLOW_PORT=5556         # instead of 5555
```

Then restart:

```bash
docker compose down
docker compose up -d
```

### File-Permission Mismatches

**Symptom**: Files in `student_workspace/` on the host are owned by `root`
instead of your user.  Or code-server cannot write to the workspace.

**Cause**: `PUID`/`PGID` in `.env` do not match your host user's IDs.

**Fix**:

1. Run `./start.sh` — it auto-detects your UID and GID and writes the correct
   values into `.env`.  If you are not using `start.sh`, verify your IDs on
   the host manually:
   ```bash
   id -u   # e.g. 1000
   id -g   # e.g. 1000
   ```

2. Update `.env` with the correct values:
   ```bash
   PUID=1000
   PGID=1000
   ```

3. Recover existing files:
   ```bash
   # On the HOST (not inside the container):
   sudo chown -R $(id -u):$(id -g) student_workspace/
   ```

4. Restart the container:
   ```bash
   docker compose down
   docker compose up -d
   ```

> **Note**: The manual `id -u`/`id -g` step is only needed when `start.sh` is
> not used.  The wrapper script handles auto-detection automatically.

### "command not found: python" / "command not found: node"

The PATH should already include `/opt/venv/bin` and `/usr/local/bin`.  If not,
source them manually:

```bash
export PATH=/opt/venv/bin:/usr/local/bin:$PATH
```

Add this to `~/.bashrc` (in the container) if it happens persistently.

### Container starts but code-server not reachable

1. Check the logs:
   ```bash
   docker compose logs code-server
   ```

2. Verify the container is running:
   ```bash
   docker compose ps
   ```

3. Ensure the port in `.env` matches the URL you are opening.  If you changed
   `CODESERVER_PORT`, open `http://localhost:<that-port>`.

### Pi provider authentication lost after restart

OAuth tokens that are not persisted in the bind-mounted workspace are lost when
the container is recreated.  See §7.3(b) for the one-time browser flow that
persists tokens into `student_workspace/` so they survive restarts.

---

## 11. Alternative AI Agents

Pi is the default assistant; alternatives are opt-in and launched manually from the terminal.

| Agent | Launch | Free-model story |
|---|---|---|
| **OpenCode** | `opencode` | Open-source AI coding agent; 75+ LLM providers via Models.dev, MCP support, free models included. MIT. |
| **Freebuff** | `freebuff` | Zero-config, ad-supported free AI agent. Bundles free models: DeepSeek V4 Flash, Kimi K2.7, MiniMax M2.7. No API key needed. |
| **gentle-ai** | `gentle-ai` | Ecosystem configurator (not an agent itself). Enhances any installed agent with persistent memory (Engram), Spec-Driven Development, curated skills, and MCP servers. |
| **MiMo** | `mimo` | MiMo (Xiaomi, fork of OpenCode) — free `mimo-auto` channel, no API key, no login, 1M context window, 128K output, vision/image input. Free for a limited time. MIT-licensed. For headless use: `mimo --dangerously-skip-permissions` or `MIMOCODE_DANGEROUSLY_SKIP_PERMISSIONS=1` (opt-in, not set by default). |
| **Qoder** | `qodercli` | Terminal-native agentic platform (NEXT code completion, Inline Chat, Ask/Agent, Quest Window for autonomous delegation). Free tier: email/Google/GitHub signup, no credit card. Qoder is a standalone agent not configured by gentle-ai. |

> **OpenSpec** (Fission-AI / OpenSpec v1.6.0) is already installed as the SDD framework for this project. It is not re-installed as an agent.
>
> **gentle-ai scope note**: gentle-ai configures OpenCode only; Pi has gentle-pi; Freebuff, MiMo, and Qoder are standalone agents not configured by gentle-ai.

Run `./agents.sh` to discover all installed agents and their launch commands.

---

## Appendix A: `.env` / `.env.example` Reference

The shipped `.env` file is ready to run with the defaults below.
`.env.example` is kept as a reference template documenting every variable.

| Variable | Default | Purpose |
|---|---|---|
| `PUID` | `1000` | Host user ID (auto-detected by `start.sh`; run `id -u` manually if needed) |
| `PGID` | `1000` | Host group ID (auto-detected by `start.sh`; run `id -g` manually if needed) |
| `TZ` | `Etc/UTC` | Container timezone |
| `PASSWORD` | `student` | code-server login password (change on shared machines) |
| `HASHED_PASSWORD` | _(empty)_ | Alternative to PASSWORD (bcrypt hash) |
| `CODESERVER_PORT` | `8443` | Host port for code-server |
| `JUPYTER_PORT` | `8888` | Host port for Jupyter |
| `MLFLOW_PORT` | `5555` | Host port for MLflow UI |
| `DEVICE` | `cpu` | `cpu` or `gpu` (GPU requires NVIDIA Toolkit) |
| `PI_FREE_ONLY` | `1` | Lock Pi to free/zero-cost providers |
| `VITE_API_BASE_URL` | `https://astryx.atmeta.com/` | Frontend API base URL (student-side) |
| `KILO_API_KEY` | _(commented)_ | Pi provider API key (optional) |
| `CLINE_API_KEY` | _(commented)_ | Pi provider API key (optional) |
| `OPENROUTER_API_KEY` | _(commented)_ | Pi provider API key (optional) |

---

## Appendix B: Quick Reference — Common Commands

```bash
# Build
docker compose build

# Start
docker compose up -d

# Stop
docker compose down

# View logs
docker compose logs -f

# Open shell inside running container
docker compose exec code-server /bin/bash

# Rebuild without cache (rare — only if a layer is stuck)
docker compose build --no-cache
```
