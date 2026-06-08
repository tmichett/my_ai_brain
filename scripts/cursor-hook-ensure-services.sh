#!/usr/bin/env bash
# Cursor sessionStart hook — ensure Open Brain + Agentic OS containers after reboot.
set -euo pipefail

REPO="${MY_AI_BRAIN_REPO:-$HOME/Github/my_ai_brain}"
exec "${REPO}/scripts/ensure-ai-brain-services.sh" --hook
