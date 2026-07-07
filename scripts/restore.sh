#!/bin/bash
# Open Brain Restore — imports thoughts from JSON backup and regenerates embeddings
# Usage: ./scripts/restore.sh [input_path]
#
# Default input: ~/Documents/MBP-M3-RH/Obsidian-Work-Vault/Obsidian-Work/open-brain-backup.json
# Requires: Ollama running with nomic-embed-text, local Supabase running

set -euo pipefail

VAULT_DIR="${VAULT_DIR:-$HOME/Documents/MBP-M3-RH/Obsidian-Work-Vault/Obsidian-Work}"
INPUT="${1:-$VAULT_DIR/open-brain-backup.json}"
DB_CONTAINER="${DB_CONTAINER:-supabase_db_travis}"
OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
OLLAMA_MODEL="${OLLAMA_EMBED_MODEL:-nomic-embed-text}"

if [ ! -f "$INPUT" ]; then
    echo "Error: Backup file not found at $INPUT"
    exit 1
fi

echo "Checking services..."
curl -sf "$OLLAMA_URL/api/tags" > /dev/null 2>&1 || { echo "Error: Ollama not running at $OLLAMA_URL"; exit 1; }
podman exec "$DB_CONTAINER" pg_isready -U postgres > /dev/null 2>&1 || { echo "Error: Supabase DB not running"; exit 1; }

COUNT=$(python3 -c "import json; d=json.load(open('$INPUT')); print(d['thought_count'])")
echo "Restoring $COUNT thoughts from: $INPUT"
echo "Embeddings will be regenerated via Ollama ($OLLAMA_MODEL)..."
echo ""

python3 << PYTHON
import json, sys, subprocess, urllib.request

input_path = "$INPUT"
ollama_url = "$OLLAMA_URL"
ollama_model = "$OLLAMA_MODEL"
db_container = "$DB_CONTAINER"

with open(input_path) as f:
    backup = json.load(f)

thoughts = backup.get("thoughts", [])
if not thoughts:
    print("No thoughts to restore.")
    sys.exit(0)

restored = 0
skipped = 0

for i, thought in enumerate(thoughts, 1):
    content = thought["content"]
    metadata = thought.get("metadata", {})
    created_at = thought.get("created_at", "now()")
    updated_at = thought.get("updated_at")

    # Generate embedding
    req = urllib.request.Request(
        f"{ollama_url}/api/embed",
        data=json.dumps({"model": ollama_model, "input": content}).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as resp:
            embed_data = json.loads(resp.read())
            embedding = embed_data["embeddings"][0]
    except Exception as e:
        print(f"  [{i}/{len(thoughts)}] SKIP (embedding failed): {str(e)[:60]}")
        skipped += 1
        continue

    # Insert into DB (skip if content already exists)
    embedding_str = json.dumps(embedding)
    metadata_str = json.dumps(metadata).replace("'", "''")
    content_escaped = content.replace("'", "''")

    sql = f"""
    INSERT INTO public.thoughts (content, embedding, metadata, created_at, updated_at)
    SELECT '{content_escaped}', '{embedding_str}'::vector, '{metadata_str}'::jsonb,
           '{created_at}'::timestamptz, {f"'{updated_at}'::timestamptz" if updated_at else "now()"}
    WHERE NOT EXISTS (
        SELECT 1 FROM public.thoughts WHERE content = '{content_escaped}'
    );
    """

    result = subprocess.run(
        ["podman", "exec", db_container, "psql", "-U", "postgres", "-c", sql],
        capture_output=True, text=True
    )

    if result.returncode != 0:
        print(f"  [{i}/{len(thoughts)}] ERROR: {result.stderr.strip()[:80]}")
        skipped += 1
    else:
        if "INSERT 0 1" in result.stdout:
            restored += 1
            print(f"  [{i}/{len(thoughts)}] Restored: {content[:60]}...")
        else:
            skipped += 1
            print(f"  [{i}/{len(thoughts)}] Already exists, skipped")

print(f"\nDone. Restored: {restored}, Skipped: {skipped}")
PYTHON
