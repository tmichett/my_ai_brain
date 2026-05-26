# Using Your AI Brain

This guide covers day-to-day usage of the AI Brain system from Cursor and Claude Code.

---

## Capturing Thoughts

Just talk naturally to Cursor. It knows how to use the Open Brain tools.

### Examples

| What you say | What happens |
|-------------|--------------|
| "Remember this: we decided to use Podman for all containers" | Captures as a `decision` with relevant topics |
| "Note that Sarah wants to move to the platform team" | Captures as `person_note` mentioning Sarah |
| "Save this idea: build a CLI tool that syncs brain to markdown" | Captures as `idea` |
| "Log this task: update Ollama to latest version next week" | Captures as `task` with action items |

### Tips for better capture

- Be specific and self-contained — the thought should make sense when retrieved months later
- The AI automatically extracts: topics, people, type, and action items
- You can specify metadata explicitly: "Capture this as a decision about architecture..."

---

## Searching Your Brain

### Semantic Search (by meaning)

```
"What did I capture about container decisions?"
"Find my notes about Sarah's career plans"
"What have I noted about API design?"
```

Semantic search finds thoughts by **meaning**, not exact keywords. "Container decisions" will match a thought about "using Podman for all services" even though the words don't overlap.

### Browsing Recent

```
"Show my thoughts from the last 3 days"
"List my recent decisions"
"What ideas have I captured this week?"
```

### Filtering

```
"Show thoughts about architecture"        → filter by topic
"List all person_notes"                    → filter by type
"What have I captured mentioning Sarah?"   → filter by person
```

### Stats

```
"How many thoughts are in my brain?"
"Give me brain stats"
```

---

## Working with Obsidian Notes

The Obsidian MCP gives Cursor direct access to your vault for structured knowledge:

```
"Read my open-brain-local-setup note"
"Search my vault for pgvector"
"Add a section about backup strategy to the setup guide"
"List everything in my Learnings folder"
```

---

## When to Use Which

| Scenario | Tool |
|----------|------|
| Quick thought, decision, observation | Open Brain (`capture_thought`) |
| Detailed guide or documentation | Obsidian (`obsidian_write_note`) |
| "What did I think about X?" | Open Brain (`search_thoughts`) |
| "Show me my setup guide" | Obsidian (`obsidian_get_note`) |
| Fleeting idea worth saving | Open Brain |
| Reference material with structure | Obsidian |

---

## Backup & Sync

### Manual backup

```bash
cd ~/Github/my_ai_brain
./scripts/backup.sh
```

Exports all thoughts as JSON to the Obsidian vault. LiveSync handles distribution to other machines.

### Restore on another machine

```bash
cd ~/Github/my_ai_brain
./scripts/restore.sh
```

### Automatic backup (via Cursor hook)

A session-end hook automatically backs up thoughts when you finish a Cursor session. No manual action needed.

---

## Thought Types

The AI classifies captured thoughts into types:

| Type | Use for |
|------|---------|
| `observation` | Things you noticed or learned passively |
| `decision` | Choices made with rationale |
| `idea` | Things to explore or build later |
| `task` | Action items and to-dos |
| `reference` | Facts, links, specs to remember |
| `person_note` | Things about specific people |
| `learning` | Lessons learned, insights |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "Ollama embedding failed" | `podman start ollama` |
| "Supabase connection refused" | `podman ps -a --filter "name=supabase_" --format "{{.Names}}" \| xargs podman start` |
| Search returns nothing | Lower threshold: "search with threshold 0.3" |
| Obsidian tools fail | Open Obsidian app (Local REST API only runs when app is open) |
| MCP server not showing in Cursor | Restart Cursor; verify `~/.cursor/mcp.json` |
