#!/bin/bash
# Open Brain Setup Verification
# Run this on any machine to check if the AI Brain is fully operational.
# All checks should print OK. Any FAIL indicates a missing step.

set -uo pipefail

echo "=== Open Brain Setup Verification ==="
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

# 1. Ollama container running
check "Ollama responding" \
    "curl -sf http://127.0.0.1:11434/api/tags" \
    "Run: podman start ollama"

# 2. Embedding model available
check "nomic-embed-text model loaded" \
    "curl -sf http://127.0.0.1:11434/api/tags | python3 -c \"import json,sys; models=[m['name'] for m in json.load(sys.stdin).get('models',[])]; assert any('nomic-embed' in m for m in models)\"" \
    "Run: podman exec ollama ollama pull nomic-embed-text"

# 3. Supabase DB running
DB_CONTAINER=$(podman ps --filter "name=supabase_db" --format "{{.Names}}" 2>/dev/null | head -1)
check "Supabase Postgres running" \
    "[ -n '$DB_CONTAINER' ] && podman exec $DB_CONTAINER pg_isready -U postgres" \
    "Run: podman ps -a --filter 'name=supabase_' --format '{{.Names}}' | xargs podman start"

# 4. Supabase REST API
check "Supabase REST API responding" \
    "curl -sf http://127.0.0.1:54321/rest/v1/ -H 'apikey: placeholder' -o /dev/null" \
    "Kong container may be down: podman start <kong_container>"

# 5. Thoughts table exists
check "thoughts table exists" \
    "podman exec $DB_CONTAINER psql -U postgres -c 'SELECT 1 FROM public.thoughts LIMIT 0;'" \
    "Run: podman exec \$DB_CONTAINER psql -U postgres < sql/001-setup.sql"

# 6. match_thoughts function exists
check "match_thoughts function exists" \
    "podman exec $DB_CONTAINER psql -U postgres -c \"SELECT 1 FROM pg_proc WHERE proname = 'match_thoughts';\" | grep -q 1" \
    "Run: podman exec \$DB_CONTAINER psql -U postgres < sql/001-setup.sql"

# 7. MCP server dependencies installed
check "MCP server node_modules present" \
    "[ -d '$HOME/Github/my_ai_brain/mcp-server/node_modules' ]" \
    "Run: cd ~/Github/my_ai_brain/mcp-server && npm install"

# 8. MCP server compiles
check "MCP server TypeScript compiles" \
    "cd $HOME/Github/my_ai_brain/mcp-server && npx tsc --noEmit" \
    "Check for TypeScript errors in src/index.ts"

# 9. Embedding generation works end-to-end
check "Embedding generation (768d)" \
    "curl -sf http://127.0.0.1:11434/api/embed -d '{\"model\":\"nomic-embed-text\",\"input\":\"test\"}' | python3 -c \"import json,sys; d=json.load(sys.stdin); assert len(d['embeddings'][0]) == 768\"" \
    "Ollama or model issue"

# 10. Cursor MCP config
check "open-brain in Cursor MCP config" \
    "grep -q 'open-brain' $HOME/.cursor/mcp.json" \
    "Add open-brain entry to ~/.cursor/mcp.json (see docs/cursor-mcp-config.json)"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ $FAIL -eq 0 ]; then
    echo "All checks passed. Open Brain is fully operational."
else
    echo "Fix the failed checks above and re-run this script."
fi

exit $FAIL
