#!/bin/bash
# Travis-Fedora Open Brain verification.
# Run on Fedora after first-time setup. Do not use Apple verify.sh as the Fedora check.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/load-ai-brain-env.sh"

REPO="${MY_AI_BRAIN_REPO:-$HOME/Github/my_ai_brain}"

echo "=== Travis-Fedora Open Brain verification ==="
echo ""

PASS=0
FAIL=0

check() {
    if eval "$2" > /dev/null 2>&1; then
        echo "  [OK]   $1"
        ((PASS++))
    else
        echo "  [FAIL] $1 — $3"
        ((FAIL++))
    fi
}

check "Ollama responding" \
    "curl -sf http://127.0.0.1:11434/api/tags" \
    "Run: podman start ollama  (first-time: docs/hosts/TRAVIS-FEDORA.md)"

check "nomic-embed-text model loaded" \
    "curl -sf http://127.0.0.1:11434/api/tags | python3 -c \"import json,sys; models=[m['name'] for m in json.load(sys.stdin).get('models',[])]; assert any('nomic-embed' in m for m in models)\"" \
    "Run: podman exec ollama ollama pull nomic-embed-text"

DB_CONTAINER=$(podman ps --filter "name=supabase_db" --format "{{.Names}}" 2>/dev/null | head -1)
check "Supabase Postgres running" \
    "[ -n '$DB_CONTAINER' ] && podman exec $DB_CONTAINER pg_isready -U postgres" \
    "Run: podman ps -a --filter 'name=supabase_' --format '{{.Names}}' | xargs podman start"

check "Supabase REST API responding" \
    "curl -sf http://127.0.0.1:54321/rest/v1/ -H 'apikey: placeholder' -o /dev/null" \
    "Kong container may be down: podman start \$(podman ps -a --filter name=supabase_kong --format '{{.Names}}')"

check "thoughts table exists" \
    "podman exec $DB_CONTAINER psql -U postgres -c 'SELECT 1 FROM public.thoughts LIMIT 0;'" \
    "Run: podman exec \$DB_CONTAINER psql -U postgres < ${REPO}/sql/001-setup.sql"

check "match_thoughts function exists" \
    "podman exec $DB_CONTAINER psql -U postgres -c \"SELECT 1 FROM pg_proc WHERE proname = 'match_thoughts';\" | grep -q 1" \
    "Run: podman exec \$DB_CONTAINER psql -U postgres < ${REPO}/sql/001-setup.sql"

check "MCP server node_modules present" \
    "[ -d '${REPO}/mcp-server/node_modules' ]" \
    "Run: cd ${REPO}/mcp-server && npm install"

check "MCP server TypeScript compiles" \
    "cd ${REPO}/mcp-server && npx tsc --noEmit" \
    "Check for TypeScript errors in src/index.ts"

check "Embedding generation (768d)" \
    "curl -sf http://127.0.0.1:11434/api/embed -d '{\"model\":\"nomic-embed-text\",\"input\":\"test\"}' | python3 -c \"import json,sys; d=json.load(sys.stdin); assert len(d['embeddings'][0]) == 768\"" \
    "Ollama or model issue"

check "open-brain in Cursor MCP config" \
    "grep -q 'open-brain' $HOME/.cursor/mcp.json" \
    "Add open-brain entry to ~/.cursor/mcp.json (this machine's key, not Apple's)"

check "thoughts_merge importable" \
    "PYTHONPATH=${SCRIPT_DIR}/lib python3 -c 'from thoughts_merge import merge_thoughts, build_envelope'" \
    "Missing scripts/lib/thoughts_merge.py"

check "brain-sync.sh present" \
    "[ -x '${SCRIPT_DIR}/brain-sync.sh' ]" \
    "Missing scripts/brain-sync.sh"

if [[ -n "${VAULT_DIR:-}" ]]; then
    check "vault directory exists" \
        "[ -d '${VAULT_DIR}' ]" \
        "Set --vault on install-ai-brain.sh (LiveSync path)"
    check "open-brain-sync directory" \
        "[ -d '${VAULT_DIR}/open-brain-sync' ]" \
        "Run: mkdir -p \"${VAULT_DIR}/open-brain-sync\""
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ $FAIL -eq 0 ]; then
    echo "All checks passed. Travis-Fedora Open Brain looks operational."
else
    echo "Fix the failed checks above and re-run this script."
fi

exit $FAIL
