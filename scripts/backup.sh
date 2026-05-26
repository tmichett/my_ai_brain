#!/bin/bash
# Open Brain Backup — exports thoughts as JSON to Obsidian vault for sync
# Usage: ./scripts/backup.sh [output_path]
#
# Default output: ~/Documents/MBP-M3-RH/Obsidian-Work-Vault/Obsidian-Work/open-brain-backup.json
# This file syncs via LiveSync to other machines.

set -euo pipefail

VAULT_DIR="${VAULT_DIR:-$HOME/Documents/MBP-M3-RH/Obsidian-Work-Vault/Obsidian-Work}"
OUTPUT="${1:-$VAULT_DIR/open-brain-backup.json}"
DB_CONTAINER="${DB_CONTAINER:-supabase_db_travis}"

echo "Exporting Open Brain thoughts..."

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
" | python3 -c "
import json, sys

raw = sys.stdin.read().strip()
if not raw or raw == '':
    data = []
else:
    data = json.loads(raw)

export = {
    'version': 1,
    'exported_at': '$(date -u +%Y-%m-%dT%H:%M:%SZ)',
    'machine': '$(hostname)',
    'thought_count': len(data),
    'thoughts': data
}

print(json.dumps(export, indent=2, default=str))
" > "$OUTPUT"

COUNT=$(python3 -c "import json; d=json.load(open('$OUTPUT')); print(d['thought_count'])")
echo "Exported $COUNT thoughts to: $OUTPUT"
echo "File size: $(du -h "$OUTPUT" | cut -f1)"
