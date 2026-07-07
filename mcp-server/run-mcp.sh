#!/usr/bin/env bash
# Launcher for Cursor MCP — stable Node path (Cursor does not load fnm/nvm shells).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load Supabase key from mcp.json when env is missing (Cursor sometimes omits env on retry).
load_open_brain_env() {
  python3 - <<'PY'
import json, os, sys
path = os.path.expanduser("~/.cursor/mcp.json")
try:
    with open(path) as f:
        env = json.load(f)["mcpServers"]["open-brain"]["env"]
except Exception as exc:
    print(f"open-brain MCP: could not read {path}: {exc}", file=sys.stderr)
    sys.exit(1)
for key in ("SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "OLLAMA_URL", "OLLAMA_EMBED_MODEL"):
    val = env.get(key) or os.environ.get(key)
    if val:
        print(f'export {key}={json.dumps(val)}')
PY
}

if [[ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  # shellcheck disable=SC1090
  eval "$(load_open_brain_env)"
fi

if [[ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  echo "open-brain MCP: SUPABASE_SERVICE_ROLE_KEY is required (set in ~/.cursor/mcp.json env)" >&2
  exit 1
fi

export SUPABASE_URL="${SUPABASE_URL:-http://127.0.0.1:54321}"
export OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
export OLLAMA_EMBED_MODEL="${OLLAMA_EMBED_MODEL:-nomic-embed-text}"

if [[ -x /usr/local/bin/node ]]; then
  NODE=/usr/local/bin/node
elif [[ -x /opt/homebrew/bin/node ]]; then
  NODE=/opt/homebrew/bin/node
else
  NODE="$(command -v node)" || {
    echo "open-brain MCP: node not found on PATH" >&2
    exit 1
  }
fi

if [[ ! -d "$DIR/node_modules/@modelcontextprotocol/sdk" ]]; then
  echo "open-brain MCP: run npm install in ${DIR}" >&2
  exit 1
fi

if [[ ! -f "$DIR/dist/index.js" ]]; then
  echo "open-brain MCP: run npm run build in ${DIR}" >&2
  exit 1
fi

exec "$NODE" "$DIR/dist/index.js"
