# Bob (IBM watsonx Code Assistant) Integration

This document covers the configuration required to use the AI Brain (Open Brain + Obsidian Vault) from **Bob** — mirroring the existing Cursor integration.

## What Was Configured

### MCP Servers (`~/.bob/settings/mcp.json`)

Both MCP servers that Cursor uses are now registered globally for Bob:

| Server | Purpose | Tools |
|--------|---------|-------|
| `open-brain` | Semantic vector memory via Ollama + Supabase | `capture_thought`, `search_thoughts`, `list_thoughts`, `thought_stats` |
| `obsidian` | Obsidian vault read/write via Local REST API | 12 tools (notes, search, tags, etc.) |

The `open-brain` server uses the same `run-mcp.sh` launcher as Cursor. The launcher was updated to check `~/.bob/settings/mcp.json` as a fallback source for credentials (before `~/.cursor/mcp.json`), making it client-agnostic.

### Bob Skills (`~/.bob/skills/`)

| Skill | Location | Purpose |
|-------|----------|---------|
| `open-brain-preflight` | `~/.bob/skills/open-brain-preflight/SKILL.md` | Preflight health check before any open-brain tool use — verifies Ollama and Supabase are running |
| `ai-knowledge-base` | `~/.bob/skills/ai-knowledge-base/SKILL.md` | Full LLM Wiki pattern: INGEST, QUERY, LINT operations with two-system memory (Obsidian + Open Brain) |

The `ai-knowledge-base` skill includes:
- `config.yaml` — vault path pre-configured to `~/Documents/MBP-M3-RH/Obsidian-Work-Vault/Obsidian-Work`
- `references/templates.md` — note type templates (Repos, Tools, Errors, Decisions, Learnings, Queries)
- `references/schema.md` — hot cache format, log format, interconnection strategy

## Bob vs Cursor Integration Map

| Component | Cursor | Bob |
|-----------|--------|-----|
| MCP config | `~/.cursor/mcp.json` | `~/.bob/settings/mcp.json` |
| open-brain MCP | ✅ | ✅ |
| obsidian MCP | ✅ | ✅ |
| Preflight rule/skill | `~/.cursor/rules/open-brain-preflight.mdc` (always-on rule) | `~/.bob/skills/open-brain-preflight/` (skill, auto-invoked) |
| AI knowledge base | `~/.cursor/skills/ai-knowledge-base/` | `~/.bob/skills/ai-knowledge-base/` |
| Session hooks (backup) | `~/.cursor/hooks.json` → `sessionEnd` | Not yet configured (see below) |
| Sleepwatcher wake reminder | `~/.wakeup` → `cursor-mcp-wake-reminder.sh` | Not needed (Bob reconnects MCP automatically) |

## Session Hooks (Not Yet Configured)

Cursor uses `~/.cursor/hooks.json` to run `cursor-hook-backup.sh` at session end. Bob does not have a direct equivalent hook system for session lifecycle events. To ensure backups happen, run manually:

```bash
cd ~/Github/my_ai_brain
./scripts/backup.sh
```

Or add it as a shell alias to run at the end of a work session.

## Prerequisites

All prerequisites are shared with the Cursor setup:

- Podman running with `ollama` and `supabase_*` containers
- Obsidian app open (Local REST API plugin active on port 27124)
- `npm install` completed in `mcp-server/`
- `npm run build` completed (produces `mcp-server/dist/index.js`)

Start everything:

```bash
~/Github/my_ai_brain/scripts/start-ai-brain.sh
```

## Verifying the Integration

1. Open Bob (IBM watsonx Code Assistant) with the `my_ai_brain` workspace.
2. Open Bob Settings → MCP tab. You should see `open-brain` and `obsidian` listed.
3. Test: ask Bob "How many thoughts are in my brain?" — it should call `thought_stats`.
4. Test: ask Bob "Read my hot.md note" — it should call the Obsidian MCP.

If either server shows as disconnected, run `./scripts/verify.sh` to diagnose.
