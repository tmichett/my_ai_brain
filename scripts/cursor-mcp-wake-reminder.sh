#!/usr/bin/env bash
# macOS sleepwatcher ~/.wakeup handler — runs after lid open / resume from sleep.
# Checks AI Brain container health; reminds you to Reload Cursor for MCP reconnect.
set -euo pipefail

REPO="${MY_AI_BRAIN_REPO:-$HOME/Github/my_ai_brain}"
ENSURE="${REPO}/scripts/ensure-ai-brain-services.sh"
LOG="${HOME}/Library/Logs/cursor-mcp-wake-reminder.log"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

{
  echo "=== $(date -Iseconds) wake ==="
  if [[ -x "$ENSURE" ]]; then
    if "$ENSURE" --check-only --quiet; then
      echo "infra: healthy"
    else
      echo "infra: unhealthy — starting services in background"
      nohup "$ENSURE" --quiet >>"${HOME}/Library/Logs/ensure-ai-brain-services.log" 2>&1 &
    fi
  else
    echo "warn: ensure script missing at ${ENSURE}"
  fi
} >>"$LOG" 2>&1 || true

/usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null || true
display notification "Reload Cursor (Cmd+Shift+P → Reload Window) to reconnect MCP servers." with title "AI Brain — after sleep"
APPLESCRIPT
