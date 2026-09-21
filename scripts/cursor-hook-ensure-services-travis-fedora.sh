#!/usr/bin/env bash
# Cursor sessionStart hook — Travis-Fedora only (do not point Apple at this).
set -euo pipefail

REPO="${MY_AI_BRAIN_REPO:-$HOME/Github/my_ai_brain}"
exec "${REPO}/scripts/ensure-ai-brain-services-travis-fedora.sh" --hook
