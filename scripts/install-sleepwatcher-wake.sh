#!/usr/bin/env bash
# Install sleepwatcher + wire ~/.wakeup to cursor-mcp-wake-reminder.sh
set -euo pipefail

REPO="${MY_AI_BRAIN_REPO:-$HOME/Github/my_ai_brain}"
WAKE_SCRIPT="${REPO}/scripts/cursor-mcp-wake-reminder.sh"
SLEEP_SCRIPT="${REPO}/scripts/cursor-mcp-sleep-noop.sh"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew required: brew install sleepwatcher" >&2
  exit 1
fi

if ! brew list sleepwatcher >/dev/null 2>&1; then
  echo "Installing sleepwatcher via Homebrew..."
  brew install sleepwatcher
fi

chmod +x "$WAKE_SCRIPT" "$SLEEP_SCRIPT"
ln -sf "$WAKE_SCRIPT" "${HOME}/.wakeup"
ln -sf "$SLEEP_SCRIPT" "${HOME}/.sleep"

echo "Linked:"
echo "  ~/.wakeup -> ${WAKE_SCRIPT}"
echo "  ~/.sleep  -> ${SLEEP_SCRIPT}"

echo "Starting sleepwatcher LaunchAgent..."
brew services restart sleepwatcher

echo ""
echo "Done. After lid close / sleep, macOS will:"
echo "  1. Run ensure-ai-brain-services.sh --check-only (start containers if down)"
echo "  2. Show a notification to Reload Cursor for MCP reconnect"
echo ""
echo "Log: ~/Library/Logs/cursor-mcp-wake-reminder.log"
