#!/usr/bin/env bash
# Travis-Fedora: start AI Brain + Agentic OS Podman containers if down.
set -euo pipefail

# Resolve ~/start-ai-brain.sh → scripts/ so sibling ensure is found.
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  _dir="$(cd "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="${_dir}/${SOURCE}"
done
SCRIPT_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
ENSURE="${SCRIPT_DIR}/ensure-ai-brain-services-travis-fedora.sh"

usage() {
  cat <<EOF
Usage: start-ai-brain-travis-fedora.sh [options]

Travis-Fedora wrapper. Do not use Apple start-ai-brain.sh on this host.

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
