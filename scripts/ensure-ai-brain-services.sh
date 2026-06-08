#!/usr/bin/env bash
# Ensure Open Brain + Agentic OS Podman containers are running.
# Used manually, from start-ai-brain.sh, and by the Cursor sessionStart hook.
set -euo pipefail

SCRIPT_NAME="${0##*/}"
WAIT_SECONDS="${WAIT_SECONDS:-8}"
OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
SUPABASE_URL="${SUPABASE_URL:-http://127.0.0.1:54321}"
DASHBOARD_URL="${DASHBOARD_URL:-http://127.0.0.1:3888}"
ENV_FILE="${HOME}/.cursor/agentic-os.env"
LOG_FILE="${HOME}/Library/Logs/ensure-ai-brain-services.log"

QUIET=0
HOOK_MODE=0
CHECK_ONLY=0
STARTED_ANY=0

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Ensure Ollama, Supabase, and agentic-os-dashboard containers are up.

Options:
  --check-only   Report status only; do not start containers
  --quiet        Minimal output (errors and warnings only)
  --hook         Cursor sessionStart mode (JSON on stdout; may start in background)
  -h, --help     Show this help

Repo: my_ai_brain/scripts/
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only) CHECK_ONLY=1; shift ;;
    --quiet) QUIET=1; shift ;;
    --hook) HOOK_MODE=1; QUIET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

export PATH="${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-}"

log() { [[ "$QUIET" -eq 1 ]] && return 0; printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
fail() { printf 'FAIL: %s\n' "$*" >&2; }

load_supabase_key() {
  python3 - <<'PY'
import json, os, sys
path = os.path.expanduser("~/.cursor/mcp.json")
try:
    with open(path) as f:
        env = json.load(f)["mcpServers"]["open-brain"]["env"]
    print(env["SUPABASE_SERVICE_ROLE_KEY"])
except Exception as exc:
    print(f"Could not read Supabase key from {path}: {exc}", file=sys.stderr)
    sys.exit(1)
PY
}

load_dashboard_secret() {
  if [[ -f "${HOME}/.local/share/agentic-os-dashboard/secret" ]]; then
    cat "${HOME}/.local/share/agentic-os-dashboard/secret"
  fi
}

ensure_podman() {
  command -v podman >/dev/null 2>&1 || { fail "podman not on PATH"; return 1; }
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if ! podman machine list --format '{{.Running}}' 2>/dev/null | grep -qx true; then
      log "Starting Podman machine..."
      podman machine start >/dev/null
    fi
  fi
}

container_running() {
  local name="$1"
  podman ps --filter "name=^${name}$" --format '{{.Names}}' 2>/dev/null | grep -qx "$name"
}

load_agentic_os_env() {
  EXPECTED_EXECUTION_MODE="${EXPECTED_EXECUTION_MODE:-local}"
  EXPECTED_MEMORY_BACKEND="${EXPECTED_MEMORY_BACKEND:-}"

  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    EXPECTED_MEMORY_BACKEND="${MEMORY_BACKEND:-$EXPECTED_MEMORY_BACKEND}"
  fi

  if [[ -z "$EXPECTED_MEMORY_BACKEND" ]]; then
    if python3 - <<'PY' >/dev/null 2>&1
import json, os
with open(os.path.expanduser("~/.cursor/mcp.json")) as f:
    json.load(f)["mcpServers"]["open-brain"]
PY
    then
      EXPECTED_MEMORY_BACKEND="open-brain"
    else
      EXPECTED_MEMORY_BACKEND="sqlite"
    fi
  fi
}

dashboard_container_env() {
  local var="$1"
  podman exec agentic-os-dashboard printenv "$var" 2>/dev/null || true
}

dashboard_config_ok() {
  local mode backend
  container_running agentic-os-dashboard || return 1
  load_agentic_os_env
  mode="$(dashboard_container_env EXECUTION_MODE)"
  backend="$(dashboard_container_env MEMORY_BACKEND)"
  [[ "${mode:-}" == "$EXPECTED_EXECUTION_MODE" ]] || return 1
  [[ "${backend:-}" == "$EXPECTED_MEMORY_BACKEND" ]] || return 1
  return 0
}

report_dashboard_config() {
  local mode backend ok=0
  load_agentic_os_env
  if ! container_running agentic-os-dashboard; then
    fail "agentic-os-dashboard container not running"
    return 1
  fi
  mode="$(dashboard_container_env EXECUTION_MODE)"
  backend="$(dashboard_container_env MEMORY_BACKEND)"
  log "  dashboard EXECUTION_MODE: ${mode:-<unset>} (expected: ${EXPECTED_EXECUTION_MODE})"
  log "  dashboard MEMORY_BACKEND: ${backend:-<unset>} (expected: ${EXPECTED_MEMORY_BACKEND})"
  if [[ "${mode:-}" != "$EXPECTED_EXECUTION_MODE" ]]; then
    warn "EXECUTION_MODE must be '${EXPECTED_EXECUTION_MODE}' so RUN queues on the host agent-runner (503 if wrong)"
    ok=1
  fi
  if [[ "${backend:-}" != "$EXPECTED_MEMORY_BACKEND" ]]; then
    warn "MEMORY_BACKEND must be '${EXPECTED_MEMORY_BACKEND}' to match Open Brain / agentic-os.env"
    ok=1
  fi
  return "$ok"
}

resolve_dashboard_script() {
  local script="${AGENTIC_OS_CONTAINER_SCRIPT:-}"
  if [[ -z "$script" && -n "${AGENTIC_OS_REPO:-}" ]]; then
    for candidate in \
      "${AGENTIC_OS_REPO}/run-container-travis.sh" \
      "${AGENTIC_OS_REPO}/run-container.sh"; do
      if [[ -x "$candidate" ]]; then
        script="$candidate"
        break
      fi
    done
  fi
  printf '%s' "$script"
}

recreate_dashboard_container() {
  local script="$1"
  load_agentic_os_env
  log "  recreating agentic-os-dashboard (env vars are set at container create time)..."
  podman stop agentic-os-dashboard >/dev/null 2>&1 || true
  podman rm agentic-os-dashboard >/dev/null 2>&1 || true
  "$script" >/dev/null
  STARTED_ANY=1
  log "  agentic-os-dashboard: recreated (EXECUTION_MODE=${EXPECTED_EXECUTION_MODE}, MEMORY_BACKEND=${EXPECTED_MEMORY_BACKEND})"
}

services_healthy() {
  local supabase_key secret
  container_running ollama || return 1
  container_running supabase_kong_travis || return 1
  container_running agentic-os-dashboard || return 1
  curl -sf --max-time 3 "${OLLAMA_URL}/api/tags" >/dev/null 2>&1 || return 1
  supabase_key="$(load_supabase_key 2>/dev/null)" || return 1
  curl -sf --max-time 3 "${SUPABASE_URL}/rest/v1/" -H "apikey: ${supabase_key}" >/dev/null 2>&1 || return 1
  secret="$(load_dashboard_secret)"
  if [[ -n "$secret" ]]; then
    curl -sf --max-time 3 -H "X-Dashboard-Token: ${secret}" "${DASHBOARD_URL}/api/skills" >/dev/null 2>&1 || return 1
  else
    curl -sf --max-time 3 "${DASHBOARD_URL}/" >/dev/null 2>&1 || return 1
  fi
  dashboard_config_ok || return 1
  return 0
}

start_container_if_needed() {
  local name="$1"
  if container_running "$name"; then
    log "  ${name}: already running"
    return 0
  fi
  if podman container exists "$name" 2>/dev/null; then
    log "  starting ${name}..."
    podman start "$name" >/dev/null
    STARTED_ANY=1
    log "  ${name}: started"
    return 0
  fi
  fail "${name} container missing — run run-container-travis.sh or see open-brain-local-setup"
  return 1
}

start_supabase_containers() {
  local name started=0
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if ! container_running "$name"; then
      log "  starting ${name}..."
      podman start "$name" >/dev/null
      started=1
      STARTED_ANY=1
    fi
  done < <(podman ps -a --filter "name=supabase_" --format "{{.Names}}")
  if [[ "$started" -eq 1 ]]; then
    log "  supabase: started stopped containers"
  else
    log "  supabase: already running"
  fi
}

start_agentic_os_dashboard() {
  local script
  load_agentic_os_env
  script="$(resolve_dashboard_script)"

  if container_running agentic-os-dashboard; then
    if dashboard_config_ok; then
      log "  agentic-os-dashboard: already running (EXECUTION_MODE=${EXPECTED_EXECUTION_MODE}, MEMORY_BACKEND=${EXPECTED_MEMORY_BACKEND})"
      return 0
    fi
    if [[ -n "$script" && -x "$script" ]]; then
      recreate_dashboard_container "$script"
      return 0
    fi
    warn "agentic-os-dashboard running with wrong EXECUTION_MODE/MEMORY_BACKEND and no container script to recreate"
    return 1
  fi

  if podman container exists agentic-os-dashboard 2>/dev/null; then
    log "  starting agentic-os-dashboard..."
    podman start agentic-os-dashboard >/dev/null
    STARTED_ANY=1
    if dashboard_config_ok; then
      log "  agentic-os-dashboard: started"
      return 0
    fi
    if [[ -n "$script" && -x "$script" ]]; then
      recreate_dashboard_container "$script"
      return 0
    fi
    warn "agentic-os-dashboard started but EXECUTION_MODE/MEMORY_BACKEND wrong — recreate manually"
    return 1
  fi

  if [[ -n "$script" && -x "$script" ]]; then
    log "  creating dashboard via ${script}..."
    "$script" >/dev/null
    STARTED_ANY=1
    log "  agentic-os-dashboard: created (EXECUTION_MODE=${EXPECTED_EXECUTION_MODE}, MEMORY_BACKEND=${EXPECTED_MEMORY_BACKEND})"
    return 0
  fi

  fail "agentic-os-dashboard missing and no container script found"
  return 1
}

kickstart_agent_runner() {
  [[ "$(uname -s)" == "Darwin" ]] || return 0
  launchctl kickstart -k "gui/$(id -u)/com.agentic-os.agent-runner" >/dev/null 2>&1 \
    || warn "could not kickstart com.agentic-os.agent-runner (run manually after login)"
}

start_all_services() {
  local failures=0
  log "Ensuring AI Brain + Agentic OS containers..."
  ensure_podman || return 1
  start_container_if_needed ollama || failures=$((failures + 1))
  start_supabase_containers || failures=$((failures + 1))
  start_agentic_os_dashboard || failures=$((failures + 1))
  if [[ "$STARTED_ANY" -eq 1 ]]; then
    log "Waiting ${WAIT_SECONDS}s for services to settle..."
    sleep "$WAIT_SECONDS"
    kickstart_agent_runner
  fi
  return "$failures"
}

run_hook() {
  cat >/dev/null || true

  if services_healthy; then
    printf '{}\n'
    exit 0
  fi

  mkdir -p "$(dirname "$LOG_FILE")"
  nohup "$0" --quiet >>"$LOG_FILE" 2>&1 &
  printf '%s\n' '{"agent_message":"AI Brain / Agentic OS services were down (likely after reboot). Starting Ollama, Supabase, and dashboard containers in the background. Open Brain and dashboard MCP tools may be unavailable for ~30 seconds. Obsidian still requires the app to be open separately."}'
  exit 0
}

main() {
  if [[ "$HOOK_MODE" -eq 1 ]]; then
    run_hook
  fi

  if [[ "$CHECK_ONLY" -eq 1 ]]; then
    if services_healthy; then
      report_dashboard_config || true
      log "All core services are healthy."
      exit 0
    fi
    container_running agentic-os-dashboard && report_dashboard_config || true
    fail "One or more core services are down or misconfigured."
    exit 1
  fi

  if services_healthy; then
    load_agentic_os_env
    log "All core services already healthy (EXECUTION_MODE=${EXPECTED_EXECUTION_MODE}, MEMORY_BACKEND=${EXPECTED_MEMORY_BACKEND})."
    exit 0
  fi

  start_all_services
}

main "$@"
