#!/usr/bin/env bash
# Source from other scripts. Does not use set -e so callers keep control.
# shellcheck disable=SC1090

_ai_brain_config="${AI_BRAIN_ENV_FILE:-${HOME}/.config/ai-brain/env}"
_agentic_env="${HOME}/.cursor/agentic-os.env"

if [[ -f "$_agentic_env" ]]; then
  # shellcheck disable=SC1090
  source "$_agentic_env"
fi
if [[ -f "$_ai_brain_config" ]]; then
  # shellcheck disable=SC1090
  source "$_ai_brain_config"
fi

AI_BRAIN_HOST="${AI_BRAIN_HOST:-${MACHINE_LABEL:-}}"
VAULT_DIR="${VAULT_DIR:-${OBSIDIAN_VAULT_DIR:-}}"
MY_AI_BRAIN_REPO="${MY_AI_BRAIN_REPO:-${HOME}/Github/my_ai_brain}"
AGENTIC_OS_REPO="${AGENTIC_OS_REPO:-${HOME}/Github/agentic-os-dashboard}"
OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
SUPABASE_URL="${SUPABASE_URL:-http://127.0.0.1:54321}"
OLLAMA_EMBED_MODEL="${OLLAMA_EMBED_MODEL:-nomic-embed-text}"

if [[ -z "${LOG_DIR:-}" ]]; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    LOG_DIR="${HOME}/Library/Logs"
  else
    LOG_DIR="${HOME}/.local/state/ai-brain"
  fi
fi
mkdir -p "$LOG_DIR" 2>/dev/null || true

if [[ -z "${DB_CONTAINER:-}" ]] && command -v podman >/dev/null 2>&1; then
  DB_CONTAINER="$(podman ps --filter "name=supabase_db" --format '{{.Names}}' 2>/dev/null | head -1 || true)"
fi

if [[ -n "${VAULT_DIR:-}" ]]; then
  OPEN_BRAIN_SYNC_JSON="${OPEN_BRAIN_SYNC_JSON:-${VAULT_DIR}/open-brain-sync/thoughts.json}"
fi

export AI_BRAIN_HOST VAULT_DIR MY_AI_BRAIN_REPO AGENTIC_OS_REPO
export DB_CONTAINER LOG_DIR OPEN_BRAIN_SYNC_JSON
export OLLAMA_URL SUPABASE_URL OLLAMA_EMBED_MODEL OBSIDIAN_VAULT_DIR
