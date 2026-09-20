#!/usr/bin/env bash
# First-time Ollama container for Travis-Fedora. Does not start Supabase (needs CLI project).
set -euo pipefail

export PATH="${HOME}/.local/bin:/usr/bin:${PATH:-}"

if ! command -v podman >/dev/null 2>&1; then
  echo "FAIL: podman not on PATH. sudo dnf install -y podman" >&2
  exit 1
fi

if podman container exists ollama 2>/dev/null; then
  echo "ollama container already exists — starting"
  podman start ollama >/dev/null
else
  echo "Creating ollama container (Travis-Fedora, native Podman)..."
  podman run -d --name ollama -p 11434:11434 -v ollama_data:/root/.ollama ollama/ollama:latest
fi

echo "Pulling nomic-embed-text (768d)..."
podman exec ollama ollama pull nomic-embed-text

if curl -sf --max-time 5 http://127.0.0.1:11434/api/tags >/dev/null; then
  echo "OK: Ollama on :11434"
else
  echo "WARN: Ollama container started but API not ready yet — retry curl http://127.0.0.1:11434/api/tags" >&2
fi

cat <<'EOF'

Ollama is ready. Next: local Supabase (new project on this host, new service-role key):

  mkdir -p "$HOME/supabase-ai-brain" && cd "$HOME/supabase-ai-brain"
  supabase init    # first time only
  supabase start

  DB=$(podman ps --filter name=supabase_db --format '{{.Names}}' | head -1)
  KONG=$(podman ps --filter name=supabase_kong --format '{{.Names}}' | head -1)
  podman exec -i "$DB" psql -U postgres < "$HOME/Github/my_ai_brain/sql/001-setup.sql"
  podman exec "$KONG" cat /home/kong/kong.yml | grep sb_secret

Put THIS machine's sb_secret into ~/.cursor/mcp.json open-brain env (never Apple's key).
Full checklist: docs/hosts/TRAVIS-FEDORA.md
EOF
