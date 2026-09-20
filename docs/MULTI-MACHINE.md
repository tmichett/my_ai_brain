# Multi-machine AI Brain (Travis)

Each Travis host runs **local** Ollama + Supabase. Obsidian **LiveSync** copies notes. Open Brain thoughts ride `open-brain-sync/thoughts.json` via **UUID union-merge** (`scripts/brain-sync.sh`). Dashboard queues and service-role keys stay **per host**.

## Hosts

| Display name | `AI_BRAIN_HOST` | Start | Dashboard wrapper | Health |
|--------------|-----------------|-------|-------------------|--------|
| Travis-Mac_Apple | `travis-mac-apple` | `~/start-ai-brain.sh` (frozen Apple scripts) | `run-container-travis.sh` | `health-check-travis.sh` |
| Travis-Fedora | `travis-fedora` | `start-ai-brain-travis-fedora.sh` | `run-container-travis-fedora.sh` | `health-check-travis-fedora.sh` |
| Travis-Mac-Intel | `travis-mac-intel` | *not in this Fedora-first drop* | — | — |

**Freeze-Apple:** do not rewrite `ensure-ai-brain-services.sh`, `start-ai-brain.sh`, `run-container-travis.sh`, `health-check-travis.sh`, `backup.sh`, `restore.sh`, `verify.sh`, or Apple cursor-hook scripts. Apple joins sync with **manual** `brain-sync`.

Shared library only: `scripts/lib/thoughts_merge.py`, `scripts/lib/brain_sync_cli.py`, `scripts/brain-sync.sh`.

Envelope `version` must be **2**. Pull never truncates the local DB if the vault JSON is empty or invalid.

## What does not sync

- Embeddings (rebuilt on pull)
- `runs.db` / dashboard secret
- `SUPABASE_SERVICE_ROLE_KEY`
- Podman container names (`supabase_db_travis` is Apple-only)

## Host docs

- [Travis-Fedora **quickstart**](hosts/TRAVIS-FEDORA-QUICKSTART.md) — install this host
- [Travis-Fedora](hosts/TRAVIS-FEDORA.md) — paths
- [Travis-Mac_Apple](hosts/TRAVIS-MAC-APPLE.md)
- Install order: [superpowers/specs/2026-09-20-host-install-checklist.md](superpowers/specs/2026-09-20-host-install-checklist.md)
- [Troubleshooting](TROUBLESHOOTING.md)
