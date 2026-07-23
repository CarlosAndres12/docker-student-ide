# =============================================================================
# docker-student-ide
# Multi-stage Dockerfile: deps stage (build) → runtime stage (final image)
# =============================================================================
# Base image: linuxserver/code-server (pinned tag, NOT :latest)
#   - Provides PUID/PGID host-permission mapping
#   - Password auth via PASSWORD / HASHED_PASSWORD env vars (never baked)
#   - Stable s6-overlay init system
# =============================================================================

# =============================================================================
# STAGE 1: deps — Install all dependencies (build toolchains, wheel caches)
# =============================================================================
FROM lscr.io/linuxserver/code-server:4.93.1 AS deps

# Prevent interactive prompts during apt
ENV DEBIAN_FRONTEND=noninteractive

# ── System Dependencies ──────────────────────────────────────────────────────
# git is needed to clone pi-free at a pinned commit.
# build-essential provides compilers for some Python wheels.
RUN apt-get update && \
    for i in $(seq 1 5); do \
        apt-get install -y --no-install-recommends --fix-missing \
            software-properties-common \
            curl \
            git \
            build-essential \
            ca-certificates \
            && break || sleep 10; \
    done && \
    rm -rf /var/lib/apt/lists/*

# ── Python 3.11 (pinned minor) via deadsnakes PPA ────────────────────────────
RUN add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    for i in $(seq 1 5); do \
        apt-get install -y --no-install-recommends --fix-missing \
            python3.11 \
            python3.11-venv \
            python3.11-dev \
            && break || sleep 10; \
    done && \
    rm -rf /var/lib/apt/lists/*

# Create the virtual environment at a known path
ENV VENV_PATH=/opt/venv
RUN python3.11 -m venv $VENV_PATH
ENV PATH=$VENV_PATH/bin:$PATH

# Upgrade pip inside the venv
RUN pip install --no-cache-dir --upgrade pip

# ── Node.js 22.23.1 (LTS "Jod", pinned minor) ────────────────────────────────
# Node 22 LTS is required by @earendil-works/pi-coding-agent (>=22.19.0).
# Download binary directly for exact version pinning (no nvm/nodenv overhead).
ENV NODE_VERSION=22.23.1
RUN curl --retry 3 --retry-delay 10 --connect-timeout 30 -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    -o /tmp/node.tar.xz && \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 && \
    rm /tmp/node.tar.xz && \
    ln -sf /usr/local/bin/node /usr/local/bin/nodejs

# ── Global npm CLI Tooling (pinned versions) ─────────────────────────────────
# These are installed globally so students can scaffold projects immediately.
# Per-project starter deps (react, axios, etc.) live in package.json — NOT here.
RUN npm install -g \
    create-vite@5.1.0 \
    typescript@5.6.2 \
    npm-check-updates@17.1.3

# ── Pi AI Assistant CLI ─────────────────────────────────────────────────────
# The real Pi CLI is @earendil-works/pi-coding-agent (provides the `pi` binary).
# NOTE: `npm install -g pi` installs a JOKE package that prints "3" — do NOT use it.
# pi-coding-agent requires Node >=22.19.0 (satisfied by Node 22 LTS above).
RUN npm install -g @earendil-works/pi-coding-agent && \
    pi install npm:gentle-pi && \
    pi install npm:gentle-engram && \
    npm exec --yes --package gentle-engram@latest -- pi-engram init

# ── Alternative AI Agents (npm globals) ─────────────────────────────────────
# OpenCode (opencode-ai) — open-source AI coding agent, 75+ LLM providers via
# Models.dev, MCP support, free models included. MIT-licensed.
# Freebuff (freebuff) — zero-config, no-API-key, ad-supported free AI agent.
# Bundles free models (DeepSeek V4 Flash, Kimi K2.7, MiniMax M2.7).
# Both are npm globals → land in /usr/local → copied to runtime via /usr/local COPY.
# @latest is used because these are fast-moving tools; record resolved versions
# in docs/deployment-guide.md at build time. Pin in a follow-up if drift matters.
RUN npm install -g opencode-ai@latest freebuff@latest && \
    opencode --version && \
    freebuff --version

# ── pi-free (GitHub-sourced, pinned commit for reproducibility) ─────────────
# pi-free is NOT from the npm registry — it is cloned from GitHub and pinned
# to a specific commit SHA.  If the install path changes in the future, check
# https://pi.dev/packages/pi-free for the current command.
# We clone to /opt/pi-free (NOT /tmp) because `pi install` records the path in
# settings.json and the package must still exist at runtime.  /tmp/pi-free would
# be deleted and break the registration.
RUN git clone https://github.com/apmantza/pi-free.git /opt/pi-free && \
    cd /opt/pi-free && \
    git checkout 6119a187afa8f444376026836b60649cac3d3621 && \
    pi install /opt/pi-free

# ── Engram Go Binary (the actual MCP server) ────────────────────────────────
# gentle-engram (npm) is only the Pi extension/adapter — it is NOT the MCP server.
# The MCP launcher in mcp.json spawns `engram mcp --tools=agent`, which requires
# the separate Go binary published at github.com/Gentleman-Programming/engram.
# Without it, the MCP connection closes immediately with exit 127 (ENOENT).
# We pin v1.19.0 and install to /usr/local/bin/engram so it is on PATH and also
# copied to the runtime stage via the existing `COPY --from=deps /usr/local`.
# Override ENGRAM_VERSION to upgrade; ENGRAM_URL can point at a remote server.
ARG ENGRAM_VERSION=1.19.0
RUN ARCH="$(dpkg --print-architecture)" && \
    case "$ARCH" in \
      amd64)  ENGRAM_ARCH=linux_amd64  ;; \
      arm64)  ENGRAM_ARCH=linux_arm64  ;; \
      *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;; \
    esac && \
    curl --retry 3 --retry-delay 10 --connect-timeout 30 -fsSL -o /tmp/engram.tar.gz \
      "https://github.com/Gentleman-Programming/engram/releases/download/v${ENGRAM_VERSION}/engram_${ENGRAM_VERSION}_${ENGRAM_ARCH}.tar.gz" && \
    tar -xzf /tmp/engram.tar.gz -C /usr/local/bin engram && \
    chmod +x /usr/local/bin/engram && \
    rm /tmp/engram.tar.gz && \
    engram --version

# ── gentle-ai (Go binary, ecosystem configurator) ──────────────────────────
# gentle-ai is NOT an AI agent — it is a configurator that enhances any installed
# agent (Pi, OpenCode, Claude Code, etc.) with persistent memory (Engram),
# Spec-Driven Development, curated skills, and MCP servers. Go binary, no runtime
# dependency after install. Pinned via GENTLE_AI_VERSION; bump in one place.
# Installed to /usr/local/bin → copied to runtime via the existing /usr/local COPY.
ARG GENTLE_AI_VERSION=2.1.10
RUN ARCH="$(dpkg --print-architecture)" && \
    case "$ARCH" in \
      amd64)  GENTLE_ARCH=linux_amd64  ;; \
      arm64)  GENTLE_ARCH=linux_arm64  ;; \
      *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;; \
    esac && \
    curl --retry 3 --retry-delay 10 --connect-timeout 30 -fsSL -o /tmp/gentle-ai.tar.gz \
      "https://github.com/Gentleman-Programming/gentle-ai/releases/download/v${GENTLE_AI_VERSION}/gentle-ai_${GENTLE_AI_VERSION}_${GENTLE_ARCH}.tar.gz" && \
    tar -xzf /tmp/gentle-ai.tar.gz -C /usr/local/bin gentle-ai && \
    chmod +x /usr/local/bin/gentle-ai && \
    rm /tmp/gentle-ai.tar.gz && \
    gentle-ai --version

# ── gentle-ai: configure OpenCode with the Gentle stack ─────────────────────
# The gentle-ai binary alone does nothing — it must RUN `install` to write
# skills/memory/SDD/persona config into each agent's config directory.
# We configure OpenCode (gentle-ai supports `opencode`; `freebuff` is unsupported
# as it is a standalone agent outside the gentle ecosystem).
# HOME=/config so config lands in /config/.config/opencode (the runtime user's
# home is /config), then we COPY that dir to the runtime stage below.
# --scope=global writes to the agent's global config dir (affects all workspaces).
# Pi is already configured by `pi install npm:gentle-*` above; this step adds the
# full Gentle stack (engram memory, SDD skills, persona, theme) to OpenCode.
ENV HOME=/config
RUN gentle-ai install --agents opencode --scope=global 2>&1 | tail -5 && \
    ls /config/.config/opencode/skills >/dev/null 2>&1 && \
    echo "OpenCode configured with gentle-ai stack" && \
    python3 -c "import json; p='/config/.config/opencode/opencode.json'; d=json.load(open(p)); \
d.get('mcp',{}).pop('engram',None) and json.dump(d, open(p,'w'), indent=2); \
print('removed engram MCP entry (redundant with engram plugin; caused TUI hang)')"

# ── MiMo (Xiaomi, fork of OpenCode) ────────────────────────────────────────
ARG MIMO_VERSION=0.1.8
# MiMo is a terminal-native AI coding agent with a free `mimo-auto` channel
# (1M context, 128K output, vision input, no API key, no login). Self-contained
# precompiled binary (Bun-compiled, no runtime dependency). MIT-licensed.
# Installed via the official Xiaomi installer with VERSION env var for pinning.
# HOME=/config (set above) → binary lands at /config/.mimocode/bin/mimo,
# copied to runtime below. The installer auto-detects OS/arch (glibc, AVX2,
# musl) and extracts from Xiaomi's FDS CDN. curl --retry handles transient
# network drops that plague large binary downloads on unstable connections.
# Pinned via ARG MIMO_VERSION (default 0.1.8); bump in one place.
# gentle-ai does NOT configure MiMo (standalone fork, outside gentle ecosystem).
RUN VERSION="$MIMO_VERSION" curl --retry 3 --retry-delay 10 --connect-timeout 30 -fsSL https://mimo.xiaomi.com/install | bash && \
    /config/.mimocode/bin/mimo --version

# ── Qoder CLI (terminal-native AI coding agent with agentic platform) ────────
# Qoder CLI (qodercli) provides NEXT code completion, Inline Chat, Ask/Agent
# Chat, and Quest Window for autonomous task delegation. Free tier requires
# email/Google/GitHub signup (no credit card). Self-contained precompiled
# binary. Installed via the official curl installer which auto-detects OS/arch,
# verifies SHA256, and delegates to `qodercli install --force` for placement.
# Binary lands at /config/.qoder/bin/qodercli/qodercli-<version> with an entry
# point symlink at /config/.local/bin/qodercli. Both are copied to runtime.
# NOT pinned to a version (installer fetches latest from Qoder's CDN manifest);
# a follow-up can pin if reproducibility matters.
# gentle-ai does NOT configure Qoder (standalone agent outside gentle ecosystem).
RUN curl --retry 3 --retry-delay 10 --connect-timeout 30 -fsSL https://qoder.com/install | bash && \
    /config/.local/bin/qodercli --version

# ── Python ML/DL Stack (CPU-only by default) ────────────────────────────────
# PyTorch CPU wheels MUST be installed from the CPU-only wheel index to avoid
# pulling multi-GB CUDA libraries.  The requirements.txt also lists torch and
# torchvision, but pip skips already-installed packages.
#
# xgboost declares a HARD dependency on nvidia-nccl-cu12 (~303 MB) even though
# it is only used for distributed GPU training.  On a CPU-only image we install
# everything normally, then strip the CUDA wheels afterward to keep the image
# lean.  xgboost, torch, and tensorflow-cpu all work fine on CPU without them.
# If you switch to the GPU variant, remove the `pip uninstall` line below.
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu \
    torch==2.4.1 \
    torchvision==0.19.1 && \
    pip install --no-cache-dir -r /tmp/requirements.txt && \
    pip uninstall -y nvidia-nccl-cu12 nvidia-cuda-nvrtc-cu12 nvidia-cuda-runtime-cu12 \
        nvidia-cublas-cu12 nvidia-cuda-cupti-cu12 nvidia-cudnn-cu12 \
        nvidia-cufft-cu12 nvidia-curand-cu12 nvidia-cusolver-cu12 \
        nvidia-cusparse-cu12 nvidia-cusparselt-cu12 nvidia-nvjitlink-cu12 \
        nvidia-nvtx-cu12 triton 2>/dev/null || true && \
    rm /tmp/requirements.txt

# =============================================================================
# STAGE 2: runtime — Minimal final image (no build toolchains or wheel caches)
# =============================================================================
FROM lscr.io/linuxserver/code-server:4.93.1

# ── Copy Python Virtual Environment from deps ────────────────────────────────
# The venv contains the full ML/DL stack pre-compiled — no build deps needed.
# The venv's `python`/`python3` are symlinks to /usr/bin/python3.11, so we MUST
# install the python3.11 binary in the runtime stage or the symlinks dangle and
# `python`/`pip`/`jupyter` all fail with "command not found".
# We add the deadsnakes PPA (same source as the deps stage) and install only the
# runtime binary (no -dev headers, no build toolchain).
RUN apt-get update && \
    for i in $(seq 1 5); do \
        apt-get install -y --no-install-recommends --fix-missing \
            software-properties-common \
            && break || sleep 10; \
    done && \
    add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    for i in $(seq 1 5); do \
        apt-get install -y --no-install-recommends --fix-missing \
            python3.11 \
            && break || sleep 10; \
    done && \
    rm -rf /var/lib/apt/lists/*
COPY --from=deps /opt/venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH

# ── Copy Node.js + Global npm Packages from deps ─────────────────────────────
# Brings node, npm, and globally-installed CLI tools; no nvm/cache carried over.
COPY --from=deps /usr/local /usr/local
RUN ln -sf /usr/local/bin/node /usr/local/bin/nodejs && \
    npm cache clean --force

# ── Pi CLI, Packages, and Config ────────────────────────────────────────────
# The `pi` binary is an npm global (copied above via /usr/local).  Pi packages
# (gentle-pi, gentle-engram, pi-free) are installed by `pi install` into
# /config/.pi/agent/ — this directory MUST be copied from the deps stage or the
# packages won't be registered at runtime.  We copy it to /config/.pi (the
# linuxserver abc user's home is /config, so this is ~/.pi for the runtime user).
COPY --from=deps /config/.pi /config/.pi
RUN chown -R abc:abc /config/.pi

# Copy the pi-free source from deps.  `pi install /opt/pi-free` recorded the
# path ../../../opt/pi-free (relative to /config/.pi/agent) in settings.json,
# so /opt/pi-free MUST exist at runtime or pi-free won't load.
COPY --from=deps /opt/pi-free /opt/pi-free

# Seed the pi-free config so students start in free-only mode by default.
# pi-free reads ~/.pi/free.json (see pi-free config.ts).  We also set the
# PI_FREE_ONLY env var as a belt-and-suspenders enforcement.
RUN printf '{\n  "free": true\n}\n' > /config/.pi/free.json && \
    chown abc:abc /config/.pi/free.json

# ── Engram MCP Server Binary ─────────────────────────────────────────────────
# The Go `engram` binary is installed in the deps stage to /usr/local/bin/engram
# (see above) and copied here via `COPY --from=deps /usr/local`.  The MCP config
# at /config/.pi/agent/mcp.json spawns `engram mcp --tools=agent`, which now
# resolves to the real binary on PATH.  No ENGRAM_BIN override is needed.
# To point Pi at a remote Engram HTTP server instead, set ENGRAM_URL in .env.

# ── OpenCode Config (gentle-ai stack) ───────────────────────────────────────
# `gentle-ai install --agents opencode` ran in the deps stage with HOME=/config
# and wrote skills/memory/SDD/persona config to /config/.config/opencode/.
# We COPY that dir here so OpenCode launches pre-configured with the Gentle
# stack (engram memory, SDD skills, persona, theme) — no manual setup needed.
# Freebuff is NOT configured by gentle-ai (unsupported; it's a standalone agent
# outside the gentle ecosystem) — it works zero-config out of the box.
COPY --from=deps /config/.config/opencode /config/.config/opencode
RUN chown -R abc:abc /config/.config/opencode

# ── MiMo Binary (Xiaomi, fork of OpenCode) ──────────────────────────────────
# The MiMo installer ran in the deps stage with HOME=/config and placed the
# self-contained binary at /config/.mimocode/bin/mimo. We COPY the whole tree
# (binary + config/cache dirs) and symlink the binary into /usr/local/bin so
# `mimo` is on PATH without shell-rc edits. Free `mimo-auto` channel works
# zero-config (no API key). gentle-ai does NOT configure MiMo (standalone fork).
COPY --from=deps /config/.mimocode /config/.mimocode
RUN chown -R abc:abc /config/.mimocode && \
    ln -sf /config/.mimocode/bin/mimo /usr/local/bin/mimo

# ── Qoder CLI Binary ─────────────────────────────────────────────────────────
# The Qoder installer placed the binary tree at /config/.qoder/ and a symlink
# entry point at /config/.local/bin/qodercli. We COPY both trees and symlink
# the entry point into /usr/local/bin so `qodercli` is on PATH without
# shell-rc edits. Neither gentle-ai nor any startup script configures Qoder.
COPY --from=deps /config/.qoder /config/.qoder
COPY --from=deps /config/.local /config/.local
RUN chown -R abc:abc /config/.qoder /config/.local && \
    ln -sf /config/.local/bin/qodercli /usr/local/bin/qodercli

# ── Pi Free-Tier Routing Configuration ───────────────────────────────────────
# Lock Pi to free/zero-cost providers by default.
# Students can toggle with `pi-free free` / `pi-free all` at runtime.
# The environment variable PI_FREE_ONLY=1 additionally enforces this.
ENV PI_FREE_ONLY=1

# ── code-server Default User Settings ───────────────────────────────────────
# Bake sensible defaults so AI agent TUIs (Pi, OpenCode, MiMo, Freebuff) running
# in the integrated terminal don't lose Ctrl+key combos to VS Code commands.
# `terminal.integrated.commandsToSkipShell` lists VS Code commands whose keybinds
# are NOT sent to the terminal when it's focused — by adding the agent-relevant
# commands here, those Ctrl combos pass through to the TUI instead of triggering
# VS Code actions.  Students can still override via the GUI settings.
# We also enable `terminal.integrated.allowChords: false` (Ctrl+K is a common TUI
# prefix) and `terminal.integrated.sendKeybindingsToShell: true` so unbound Ctrl
# combos go straight to the terminal.
RUN mkdir -p /config/data/User && \
    printf '{\n\
  "terminal.integrated.sendKeybindingsToShell": true,\n\
  "terminal.integrated.allowChords": false,\n\
  "terminal.integrated.commandsToSkipShell": [\n\
    "editor.action.clipboardCopyAction",\n\
    "editor.action.clipboardPasteAction",\n\
    "editor.action.clipboardCutAction",\n\
    "workbench.action.terminal.focus",\n\
    "workbench.action.terminal.kill",\n\
    "workbench.action.terminal.new",\n\
    "workbench.action.terminal.split",\n\
    "workbench.action.terminal.toggleTerminal",\n\
    "workbench.action.quickOpen",\n\
    "workbench.action.findInFiles",\n\
    "editor.action.commentLine",\n\
    "editor.action.formatDocument"\n\
  ]\n\
}\n' > /config/data/User/settings.json && \
    chown -R abc:abc /config/data/User

# ── code-server Extensions (Open VSX Registry) ──────────────────────────────
# Pre-install 14 essential extensions in 5 categories so students start with
# a productive IDE on first launch. All IDs resolve against open-vsx.org
# (code-server's default registry). Installed as root pointing to abc's home
# (/config) so extensions land in /config/.local/share/code-server/extensions/.
# chown at end ensures correct abc:abc ownership. The full binary path
# /app/code-server/bin/code-server is used because /app/code-server/bin
# is NOT on the default PATH.
# Categories: Jupyter/Data Science (3), DevOps (1), API/Web (3),
# Productivity (4), Documentation (2), Python Development (1).
# NOTE: ms-python.vscode-pylance is proprietary (Microsoft marketplace only).
# NOTE: ms-azuretools.vscode-docker incompatible with code-server 1.93.1.
# NOTE: usernamehw.errorlens is the Open VSX ID (no hyphen before "lens").
RUN export HOME=/config && \
    /app/code-server/bin/code-server --install-extension ms-toolsai.jupyter && \
    /app/code-server/bin/code-server --install-extension ms-toolsai.jupyter-renderers && \
    /app/code-server/bin/code-server --install-extension ms-toolsai.vscode-jupyter-cell-tags && \
    /app/code-server/bin/code-server --install-extension redhat.vscode-yaml && \
    /app/code-server/bin/code-server --install-extension humao.rest-client && \
    /app/code-server/bin/code-server --install-extension bradlc.vscode-tailwindcss && \
    /app/code-server/bin/code-server --install-extension christian-kohler.path-intellisense && \
    /app/code-server/bin/code-server --install-extension usernamehw.errorlens && \
    /app/code-server/bin/code-server --install-extension Gruntfuggly.todo-tree && \
    /app/code-server/bin/code-server --install-extension oderwat.indent-rainbow && \
    /app/code-server/bin/code-server --install-extension esbenp.prettier-vscode && \
    /app/code-server/bin/code-server --install-extension yzhang.markdown-all-in-one && \
    /app/code-server/bin/code-server --install-extension bierner.markdown-mermaid && \
    /app/code-server/bin/code-server --install-extension ms-python.python && \
    chown -R abc:abc /config/.local/share/code-server/extensions

# ── No Password Hardcoded ────────────────────────────────────────────────────
# code-server's password is NEVER set in the Dockerfile.
# It MUST be provided at runtime via the PASSWORD or HASHED_PASSWORD
# environment variable in .env / docker-compose.yml.
# The linuxserver base image reads these variables automatically.

# ── Workspace Directory ──────────────────────────────────────────────────────
# docker-compose bind-mounts ./student_workspace to /config/workspace.
# This is code-server's default open directory.
# No files are baked into this path in the image.

# ── Labels ───────────────────────────────────────────────────────────────────
LABEL org.opencontainers.image.title="docker-student-ide" \
      org.opencontainers.image.description="Browser-based IDE with Node 22, Python 3.11 ML/DL stack, Jupyter, MLflow, and Pi AI assistant" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.base.name="lscr.io/linuxserver/code-server:4.93.1" \
      org.opencontainers.image.source="https://github.com/apmantza/pi-free"
