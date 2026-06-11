# My AI Brain

A local-only AI knowledge system combining **Obsidian** (structured notes) with **Open Brain** (semantic vector memory), accessible via MCP from Cursor and Claude Code. Zero cloud dependencies.

## Architecture

```
Cursor / Claude Code
    ├── Obsidian MCP (12 tools) ──→ Obsidian App ──→ Markdown Vault
    └── Open Brain MCP (4 tools) ──→ Ollama (embeddings)
                                  └─→ Supabase (pgvector storage)
```

All services run locally via Podman containers.

## Quick Start (new machine)

### Prerequisites

- Podman
- Node.js 20+
- Supabase CLI (`brew install supabase/tap/supabase`)

### 1. Start infrastructure

```bash
# Initialize and start local Supabase
cd ~/supabase  # or wherever your supabase project lives
supabase init  # only first time
supabase start

# Start Ollama container
podman run -d --name ollama -p 11434:11434 -v ollama_data:/root/.ollama ollama/ollama:latest
podman exec ollama ollama pull nomic-embed-text
```

### 2. Setup database

```bash
# Get your DB container name (e.g., supabase_db_<project_id>)
podman ps | grep supabase_db

# Run the schema setup
podman exec <db_container> psql -U postgres < sql/001-setup.sql
```

### 3. Install MCP server

```bash
cd mcp-server
npm install
```

### 4. Get service role key

```bash
podman exec <kong_container> cat /home/kong/kong.yml | grep sb_secret
```

### 5. Configure Cursor

Add to `~/.cursor/mcp.json` (see `docs/cursor-mcp-config.json` for template):

```json
"open-brain": {
  "command": "npx",
  "args": ["tsx", "/path/to/my_ai_brain/mcp-server/src/index.ts"],
  "env": {
    "SUPABASE_URL": "http://127.0.0.1:54321",
    "SUPABASE_SERVICE_ROLE_KEY": "<your-key>",
    "OLLAMA_URL": "http://127.0.0.1:11434",
    "OLLAMA_EMBED_MODEL": "nomic-embed-text"
  }
}
```

### 6. Restore from backup (if synced via LiveSync)

```bash
./scripts/restore.sh /path/to/vault/open-brain-backup.json
```

## Daily Usage

### After reboot

```bash
./scripts/start-ai-brain.sh
# or from anywhere (symlink): ~/start-ai-brain.sh
```

Starts Ollama, Supabase, and Agentic OS dashboard containers if down. A Cursor `sessionStart` hook runs the same check automatically when you open a new agent session.

Manual equivalent:

```bash
podman start ollama
podman ps -a --filter "name=supabase_" --format "{{.Names}}" | xargs podman start
```

A Cursor rule (`open-brain-preflight.mdc`) also auto-checks Open Brain services before MCP use.

### Backup

```bash
./scripts/backup.sh
```

Exports thoughts as JSON to the Obsidian vault. Syncs to other machines via LiveSync.

### Restore

```bash
./scripts/restore.sh [path/to/backup.json]
```

Imports thoughts and regenerates embeddings locally. Skips duplicates.

## Project Structure

```
my_ai_brain/
├── README.md
├── mcp-server/           # Open Brain MCP server (Node.js/TypeScript)
│   ├── package.json
│   ├── tsconfig.json
│   └── src/
│       └── index.ts      # MCP server implementation
├── canvases/             # Cursor IDE interactive canvases (.canvas.tsx)
│   ├── course-build-workflow.canvas.tsx
│   └── README.md
├── assets/diagrams/      # Static SVG/PNG exports for Obsidian
├── visualizations/       # Standalone Vite apps (browser, no Cursor)
│   └── course-build-workflow/
├── scripts/
│   ├── backup.sh         # Export thoughts to JSON (for vault sync)
│   ├── restore.sh        # Import thoughts + regenerate embeddings
│   ├── verify.sh         # Health check all components
│   ├── setup-canvas-sdk.sh  # Link canvases into Cursor + install type stubs
│   ├── generate-course-build-workflow-diagram.py  # SVG/PNG for Obsidian
│   ├── ensure-ai-brain-services.sh  # Start Ollama/Supabase/dashboard if down
│   ├── start-ai-brain.sh            # Wrapper for ensure script
│   ├── cursor-hook-ensure-services.sh  # Cursor sessionStart hook
│   └── cursor-hook-backup.sh        # Cursor sessionEnd backup hook
├── sql/
│   └── 001-setup.sql     # Database schema (pgvector, thoughts table, RLS)
└── docs/
    └── cursor-mcp-config.json  # Cursor MCP config template
```

## Usage Guide

See [docs/USAGE.md](docs/USAGE.md) for complete usage instructions including:
- How to capture thoughts naturally from Cursor
- Semantic search examples
- When to use Open Brain vs Obsidian
- Thought types and metadata

---

## MCP Tools

| Tool | Description |
|------|-------------|
| `capture_thought` | Store content + metadata, generate embedding |
| `search_thoughts` | Semantic similarity search (by meaning) |
| `list_thoughts` | Browse recent with filters (type, topic, person, days) |
| `thought_stats` | Totals, type distribution, top topics, people |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SUPABASE_URL` | `http://127.0.0.1:54321` | Local Supabase REST API |
| `SUPABASE_SERVICE_ROLE_KEY` | *(required)* | From Kong config |
| `OLLAMA_URL` | `http://127.0.0.1:11434` | Ollama API endpoint |
| `OLLAMA_EMBED_MODEL` | `nomic-embed-text` | Embedding model (768d) |
| `VAULT_DIR` | `~/Documents/.../Obsidian-Work/` | Vault path (for backup scripts) |
| `DB_CONTAINER` | `supabase_db_travis` | Postgres container name |

## Verify Setup

Run on any machine to confirm everything is working:

```bash
./scripts/verify.sh
```

Reports OK/FAIL for each component (Ollama, Supabase, DB schema, MCP server, embeddings, Cursor config).

---

## Multi-Machine Sync

The backup/restore strategy uses Obsidian LiveSync:

1. **Machine A**: Capture thoughts → `backup.sh` → JSON lands in vault
2. **LiveSync**: Vault (including backup JSON) syncs to Machine B
3. **Machine B**: `restore.sh` reads JSON, regenerates embeddings locally

Embeddings are NOT synced (they're 768 floats per thought). They're regenerated on each machine from the same model, producing identical vectors.

---

## Platform Notes

### macOS

```bash
brew install podman node supabase/tap/supabase
podman machine init && podman machine start
```

### Linux (Fedora/RHEL)

```bash
sudo dnf install -y podman nodejs npm
npm install -g supabase
```

### Linux (Ubuntu/Debian)

```bash
sudo apt install -y podman nodejs npm
npm install -g supabase
```

### Key differences by platform

| Item | macOS | Linux |
|------|-------|-------|
| Home dir | `/Users/<user>/` | `/home/<user>/` |
| Podman machine | Required (`podman machine init`) | Not needed (native) |
| Package manager | Homebrew | dnf / apt |
| Obsidian vault path | Set in `VAULT_DIR` | Set in `VAULT_DIR` |
