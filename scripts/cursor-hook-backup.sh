#!/bin/bash
# Cursor Hook: Automatic Open Brain backup on session end
# Exports thoughts as JSON to Obsidian vault for LiveSync distribution.
# Runs silently — only logs on error.

set -uo pipefail

VAULT_DIR="${VAULT_DIR:-$HOME/Documents/MBP-M3-RH/Obsidian-Work-Vault/Obsidian-Work}"
OUTPUT="$VAULT_DIR/open-brain-backup.json"
DB_CONTAINER="${DB_CONTAINER:-supabase_db_travis}"

# Check if Supabase is running; skip silently if not
podman exec "$DB_CONTAINER" pg_isready -U postgres > /dev/null 2>&1 || exit 0

# Check if thoughts table has any data
COUNT=$(podman exec "$DB_CONTAINER" psql -U postgres -t -A -c "SELECT count(*) FROM public.thoughts;" 2>/dev/null)
[ -z "$COUNT" ] || [ "$COUNT" = "0" ] && exit 0

# Export
podman exec "$DB_CONTAINER" psql -U postgres -t -A -c "
SELECT json_agg(
  json_build_object(
    'id', id,
    'content', content,
    'metadata', metadata,
    'created_at', created_at,
    'updated_at', updated_at
  ) ORDER BY created_at ASC
)
FROM public.thoughts;
" 2>/dev/null | python3 -c "
import json, sys, datetime
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
data = json.loads(raw)
export = {
    'version': 1,
    'exported_at': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'machine': '$(hostname)',
    'thought_count': len(data),
    'thoughts': data
}
print(json.dumps(export, indent=2, default=str))
" > "$OUTPUT" 2>/dev/null

exit 0
