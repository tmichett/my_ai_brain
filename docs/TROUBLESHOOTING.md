# Troubleshooting (AI Brain / Open Brain)

## Which start command?

| Host | Do this | Do not |
|------|---------|--------|
| Travis-Mac_Apple | `~/start-ai-brain.sh` → Apple `ensure-ai-brain-services.sh` | Fedora/Intel ensure scripts |
| Travis-Fedora | `~/start-ai-brain.sh` → `start-ai-brain-travis-fedora.sh` | Apple `ensure-ai-brain-services.sh`, `run-container-travis.sh` |

`bash -n` of Fedora scripts on the M3 is fine. **Running** Fedora `ensure` on Apple is not (wrong dashboard wrapper, `~/.local/state` logs, no LaunchAgents).

## `supabase_db_travis` / `supabase_kong_travis`

Those names are **Apple’s** local Supabase project. Fedora discovers `supabase_db*` / `supabase_kong*` and must use **this host’s** containers and service-role key.

## `brain-sync` drift

```bash
cd ~/Github/my_ai_brain
./scripts/brain-sync.sh status
```

- `only-local > 0` → `brain-sync.sh push` before you leave
- `only-vault > 0` → wait for LiveSync, then `brain-sync.sh pull`
- `thoughts.json` is **0 bytes** → **do not pull**; push from a host that still has rows
- Invalid JSON → pull is a no-op (local DB unchanged)

Apple `backup.sh` / `restore.sh` are **legacy dump-replace**. They are not the multi-machine sync.

## Fedora: services missing after reboot

```bash
podman start ollama
podman ps -a --filter "name=supabase_" --format "{{.Names}}" | xargs podman start
~/start-ai-brain.sh
```

If `ollama` never existed: `./scripts/bootstrap-open-brain-travis-fedora.sh`.

## Fedora: dashboard cannot read the vault (SELinux)

`run-container.sh` bind-mounts with `:z`. Recreate the container via `./run-container-travis-fedora.sh`. Confirm `podman exec agentic-os-dashboard test -r /data/vault/hot.md`.

## Fedora: Open Brain MCP red in Cursor

- `run-mcp.sh` needs `/usr/bin/node` (or PATH `node`) and `mcp-server/dist/index.js` (`npm run build`)
- `SUPABASE_SERVICE_ROLE_KEY` must be **this** machine’s `sb_secret`, not Apple’s
- After sleep: Cursor **Reload Window** (no sleepwatcher)

## Dashboard memory API 503

Expected when `MEMORY_BACKEND=open-brain`. Health-check treats 503 as pass. Use Open Brain MCP, not `/api/memory/*`.
