#!/bin/sh
# agents.sh — Discovery launcher for installed AI agents in docker-student-ide.
# Lists each agent binary found on PATH with its one-line launch command.
# Only lists agents whose binaries are present, so it stays correct if an
# agent is removed. Pi is the default; alternatives are opt-in.
#
# Usage:
#   ./agents.sh                  # from repo root on the host
#   agents.sh                    # inside the container (on PATH via bind mount)
#   bash agents.sh               # explicit shell

set -eu

# Each entry: "name|binary|launch command|one-line note"
# Pi is listed first as the default.
AGENTS="
Pi|pi|pi|Asistente por defecto — capa gratuita via pi-free
OpenCode|opencode|opencode|75+ proveedores via Models.dev, MCP, modelos gratuitos
Freebuff|freebuff|freebuff|Zero-config, sin API key, modelos gratuitos (con ads)
MiMo|mimo|mimo|Canal gratuito mimo-auto, sin API key, contexto 1M tokens (Xiaomi)
gentle-ai|gentle-ai|gentle-ai|Configurador de ecosistema (memoria Engram, SDD, skills)
"

printf '%-12s %-12s %s\n' "AGENTE" "BINARIO" "COMANDO"
printf '%-12s %-12s %s\n' "------" "-------" "--------"

# shellcheck disable=SC2034
echo "$AGENTS" | while IFS='|' read -r name bin launch note; do
  [ -z "$name" ] && continue
  if command -v "$bin" >/dev/null 2>&1; then
    printf '%-12s %-12s %s\n' "$name" "$bin" "$launch"
  fi
done

echo
echo "Pi es el asistente por defecto. Las alternativas son opcionales y se lanzan manualmente."
echo "Ejecuta 'gentle-ai' para configurar memoria/SDD/skills en cualquier agente instalado."