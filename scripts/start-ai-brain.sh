#!/usr/bin/env bash
# Start AI Brain + Agentic OS Podman containers if down.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENSURE="${SCRIPT_DIR}/ensure-ai-brain-services.sh"

usage() {
  cat <<EOF
Usage: start-ai-brain.sh [options]

Options:
  --check-only   Check status only; do not start containers
  -h, --help     Show this help

Repo: my_ai_brain/scripts/
EOF
}

args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only) args+=(--check-only); shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -x "$ENSURE" ]]; then
  echo "Missing ${ENSURE}" >&2
  exit 1
fi

exec "$ENSURE" ${args[@]+"${args[@]}"}
