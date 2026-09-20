#!/usr/bin/env bash
# UUID union-merge sync for Open Brain thoughts via the LiveSync vault file.
# Usage: brain-sync.sh [--hook] pull|push|status
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/load-ai-brain-env.sh"

export PYTHONPATH="${SCRIPT_DIR}/lib${PYTHONPATH:+:${PYTHONPATH}}"

if [[ -z "${VAULT_DIR:-}" ]]; then
  echo "FAIL: VAULT_DIR / OBSIDIAN_VAULT_DIR is unset. Pass --vault to install-ai-brain.sh or export it." >&2
  exit 1
fi

exec python3 "${SCRIPT_DIR}/lib/brain_sync_cli.py" "$@"
