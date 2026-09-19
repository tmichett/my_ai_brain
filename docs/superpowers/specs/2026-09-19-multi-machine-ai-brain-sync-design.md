# Multi-machine AI Brain + Open Brain sync — Design Spec

**Date:** 2026-09-19  
**Status:** Approved for planning; **not implemented in this session**  
**Repos:** `my_ai_brain` (sync, Open Brain, host runbooks) and `agentic-os-dashboard` (portable dashboard, health-check, snapshots)

## Goal

Run the same **offline-first** AI Brain stack on three Travis machines, without a shared remote Supabase, without losing thoughts when switching hosts during the day, and with documentation that is obviously Travis-owned.

Obsidian LiveSync already replicates the vault. Open Brain must use that same bus: a versioned JSON envelope in the vault, merged by thought UUID.

## Host names (locked)

Use these names in filenames, `MACHINE_LABEL`, wrappers, health-check output, and prose. Do not use generic labels like “other Mac” or “linux example.”

| Display name | `MACHINE_LABEL` / `AI_BRAIN_HOST` | Hardware | Role today |
|--------------|-----------------------------------|----------|------------|
| **Travis-Mac_Apple** | `travis-mac-apple` | Apple Silicon M3 (current daily driver) | Source of truth for paths that already work; keep `run-container-travis.sh` as a compatibility alias |
| **Travis-Mac-Intel** | `travis-mac-intel` | Intel macOS (new) | Same architecture as Apple, different Homebrew prefix and vault path |
| **Travis-Fedora** | `travis-fedora` | Fedora Linux | Native Podman, user systemd, SELinux |

### Canonical doc filenames

**`my_ai_brain` (Open Brain, sync, startup, troubleshooting):**

- `docs/MULTI-MACHINE.md` — topology, union-merge rules, what does not sync
- `docs/TROUBLESHOOTING.md` — failure catalog
- `docs/hosts/TRAVIS-MAC-APPLE.md`
- `docs/hosts/TRAVIS-MAC-INTEL.md`
- `docs/hosts/TRAVIS-FEDORA.md`

**`agentic-os-dashboard` (dashboard, Cursor bridge, health-check, snapshots):**

- `docs/TRAVIS-MAC-APPLE.md` — evolve from today’s `docs/TRAVIS-MACOS-SETUP.md` (leave a stub that points at the new name)
- `docs/TRAVIS-MAC-INTEL.md`
- `docs/TRAVIS-FEDORA.md`
- Update `docs/PORTABLE-SETUP.md` to index the three Travis host docs first, then generic portable notes

Each host doc must say in the first paragraph which Travis machine it belongs to, the `MACHINE_LABEL`, and the sibling doc in the other repo.

## Non-goals (this project)

- Cloud-hosted Supabase or a single always-on Open Brain that secondaries dial into
- Syncing dashboard `runs.db`, `DASHBOARD_SECRET`, or per-instance `SUPABASE_SERVICE_ROLE_KEY`
- CRDT / per-thought files / multi-master conflict UI (out of scope until simultaneous capture actually loses data)
- Implementing any of this in the session that produced this spec

## Architecture

```
Travis-Mac_Apple / Travis-Mac-Intel / Travis-Fedora
  Cursor ── open-brain MCP ── 127.0.0.1 Ollama :11434
                           └─ 127.0.0.1 Supabase :54321  (local thoughts + pgvector)
  Cursor ── obsidian MCP ── local Obsidian (LiveSync vault)
  Cursor ── dashboard MCP ── local dashboard :3888

Sync plane (vault, already LiveSync’d):
  public.thoughts.id  <──pull insert missing──  open-brain-sync/thoughts.json
                      ──push UUID union──►
```

Each machine is a full local stack. Capture never depends on another host being online. When LiveSync is reachable, the JSON envelope distributes IDs; local Ollama re-embeds on pull.

### What syncs vs what stays local

| Data | Sync? | Mechanism |
|------|-------|-----------|
| Thought `id`, `content`, `metadata`, `created_at`, `updated_at` | Yes | Vault JSON + UUID union-merge |
| Embeddings (768d) | No | Regenerated with `nomic-embed-text` on pull |
| Obsidian notes, `hot.md`, Daily Notes | Yes | Existing LiveSync |
| Dashboard `runs.db`, Kanban runtime, API secret | No | Per machine |
| `~/.cursor/mcp.json` service-role key | No | Unique per local Supabase |
| Cursor skills/rules | Git + `setup-cursor-bridge.sh`, not LiveSync | Per machine render of `KB_DIR` |

## Sync protocol (must not lose data)

### Why today’s scripts are unsafe

- `scripts/backup.sh` **replaces** `open-brain-backup.json` with **this machine’s** full dump.
- LiveSync last-writer-wins that one file.
- `scripts/restore.sh` **drops UUIDs** and skips rows by `content` text, so round-trip identity is lost.
- Session-end hook uses the same replace dump.

If Travis-Mac_Apple captures in the morning and Travis-Fedora dumps in the afternoon without merging first, the JSON can drop Apple’s new IDs. They still exist in Apple’s Postgres, but the sync file no longer carries them. Fedora never sees them until Apple dumps again **after** a correct merge.

### Required behavior: UUID union-merge

**Envelope** (vault-relative path `open-brain-sync/thoughts.json`):

```json
{
  "version": 2,
  "exported_at": "2026-09-19T14:00:00Z",
  "machine": "travis-mac-apple",
  "thought_count": 0,
  "thoughts": [
    {
      "id": "uuid",
      "content": "standalone thought text",
      "metadata": {},
      "created_at": "timestamptz",
      "updated_at": "timestamptz"
    }
  ]
}
```

`thought_count` must equal `len(thoughts)`.

**Push (`brain-sync push`):**

1. Load vault JSON if present and valid `version >= 2`. Invalid, missing, or **zero-byte** file → treat vault side as empty list (do not abort push; this is how a LiveSync wipe is repaired from a healthy local DB).
2. Dump local `public.thoughts` including `id`.
3. Merge by `id`:
   - ID only in vault → keep vault row
   - ID only in local → keep local row
   - ID in both → keep row with newer `updated_at`; if timestamps equal, keep local
4. Atomic write: temp file in the same directory, `fsync`, rename onto `thoughts.json`.
5. Also leave a one-line pointer or continue writing legacy `open-brain-backup.json` **only during a documented migration window**, and only as a **copy of the merged envelope**, never as a replace-from-local-only dump.

**Pull (`brain-sync pull`):**

1. If vault file missing, empty, or JSON invalid → **no-op** (do not truncate local DB). Warn. Exit 0 for hooks; exit 2 for interactive.
2. For each thought ID not in local DB: `INSERT` with the **same UUID**, then embed via local Ollama. Skip IDs already present (do not overwrite local content on pull; push already resolved conflicts by `updated_at`).
3. Do not dedupe by `content`. Two different IDs with similar text both stay.

**Status (`brain-sync status`):**

- Local count, vault count, IDs only-local, IDs only-vault, envelope `exported_at` age, envelope `machine`.
- Warn if vault file is older than 7 days or zero bytes.
- Warn if only-vault > 0 (you should pull) or only-local > 0 (you should push).

### Hook timing

| Event | Action |
|-------|--------|
| `start-ai-brain.sh` after services healthy | `brain-sync pull` then optional status |
| Cursor `sessionStart` (after ensure-services) | `brain-sync pull` (warn-only; never block Cursor) |
| Cursor `sessionEnd` | `brain-sync push` (replaces today’s replace-dump hook) |
| Manual | `brain-sync pull\|push\|status` |

Simultaneous capture on two machines the same minute can still race LiveSync on one file. Document: pull at session start; if `status` shows unexpected only-vault after a dual session, pull then push on the machine with the larger local count. Dated snapshots recover true loss.

### LiveSync wipe (known vault incident)

LiveSync has zeroed files (`hot.md`, repo profiles). Pull **must not** apply an empty envelope to Postgres. Push from a machine that still has rows rebuilds the JSON. Snapshots are the backup if every local DB is wrong.

## Machine configuration

Single sourced file: `~/.config/ai-brain/env` (mode `0600`). `scripts/lib/load-ai-brain-env.sh` also reads `~/.cursor/agentic-os.env` for dashboard overlap. Host values win over defaults. **No hardcoded** `MBP-M3-RH`, `supabase_db_travis`, or `~/Library/Logs` in new or rewritten scripts.

Required keys:

```bash
AI_BRAIN_HOST=travis-mac-apple    # travis-mac-intel | travis-fedora
VAULT_DIR=/absolute/path/to/Obsidian-Work
MY_AI_BRAIN_REPO=/absolute/path/to/my_ai_brain
AGENTIC_OS_REPO=/absolute/path/to/agentic-os-dashboard
# DB_CONTAINER discovered if unset: first podman name matching supabase_db
LOG_DIR=                          # Apple/Intel: ~/Library/Logs
                                  # Fedora: ~/.local/state/ai-brain
OPEN_BRAIN_SYNC_JSON="${VAULT_DIR}/open-brain-sync/thoughts.json"
OLLAMA_URL=http://127.0.0.1:11434
SUPABASE_URL=http://127.0.0.1:54321
OLLAMA_EMBED_MODEL=nomic-embed-text
```

`OBSIDIAN_VAULT_DIR`, `KB_DIR` (trailing slash in the Cursor rule), and `VAULT_DIR` must be the **same directory** on that host. `setup-cursor-bridge.sh --vault` remains the renderer for `ai-knowledge-base.mdc` (never symlink that rule).

Installer `scripts/install-ai-brain.sh`:

1. Detect OS (`Darwin` + `uname -m` vs `Linux`).
2. Prompt or `--host=` for the three Travis labels.
3. Prompt vault path; verify `hot.md` or `AI Brain/hot.md`.
4. Write `~/.config/ai-brain/env`.
5. Symlink `~/start-ai-brain.sh`.
6. `npm install` in `mcp-server`.
7. Print next step: `setup-cursor-bridge.sh --vault … --memory-backend open-brain --brain-read-gate`.

Intel Homebrew is `/usr/local`; Apple Silicon is `/opt/homebrew`. Ensure scripts prepend both. Fedora uses `/usr/bin` + `~/.local/bin`.

## Per-host stacks

### Travis-Mac_Apple (current)

Keep working paths as the reference implementation:

- Vault: `/Users/travis/Documents/MBP-M3-RH/Obsidian-Work-Vault/Obsidian-Work`
- Repos: `/Users/travis/Github/{my_ai_brain,agentic-os-dashboard}`
- Wrapper: `run-container-travis-mac-apple.sh`; **keep** `run-container-travis.sh` as a thin exec alias
- LaunchAgents: `com.agentic-os.dashboard`, `com.agentic-os.agent-runner`
- sleepwatcher wake reminder (macOS only)
- `health-check-travis.sh` becomes an alias to portable `health-check.sh` with `AI_BRAIN_HOST=travis-mac-apple`
- `CURSOR_BRAIN_GATE_MODE=enforce` may stay on this host; others default `advisory` unless Travis sets enforce

### Travis-Mac-Intel (new)

Same software as Apple, with these differences called out in `docs/hosts/TRAVIS-MAC-INTEL.md` and `agentic-os-dashboard/docs/TRAVIS-MAC-INTEL.md`:

- Homebrew prefix `/usr/local` (PATH, `flock`, sleepwatcher)
- `podman machine` required
- Vault path **unknown until install** — installer writes whatever LiveSync replica path Travis chooses; docs use `$VAULT_DIR` not a copied M3 path
- Stale Intel `/usr/local/bin/git` (2.23) **must** be called out: agent `--trailer` needs git ≥ 2.42 (already documented on Apple as a leftover Intel installer)
- headroom-ai: native x86_64 Python, not the Apple Silicon arm64 helper
- Own `run-container-travis-mac-intel.sh` (vault export only; do not copy M3 absolute paths)
- LaunchAgents yes; headless runner optional
- sleepwatcher optional (same scripts)

### Travis-Fedora

Called **Travis-Fedora** everywhere (docs, units, comments). Differences:

- `dnf install podman nodejs npm jq util-linux`; Supabase CLI per my_ai_brain README
- **No** `podman machine`
- Volume `:z` SELinux on dashboard vault mount (existing `run-container.sh`)
- `scripts/install-agentic-os-systemd.sh` for dashboard/runner (runner optional)
- `LOG_DIR=$HOME/.local/state/ai-brain` — **never** `~/Library/Logs`
- No sleepwatcher; troubleshooting says Reload Cursor window after suspend
- Own `run-container-travis-fedora.sh`
- Health-check uses systemd `--user` status instead of `launchctl`

Dashboard on Intel and Fedora is **local** (same UI, local queue). It is not a replica of Apple’s `runs.db`. Skills come from git + bridge setup. Headless `agent-runner` is optional; Cursor chat pickup is enough.

## Backups (disaster recovery — not the sync plane)

| Layer | What | Where |
|-------|------|--------|
| 1 Sync envelope | Merged thoughts JSON | Vault `open-brain-sync/thoughts.json` via LiveSync |
| 2 Dated snapshots | Vault tarball, local `pg_dump` of `public`, thoughts JSON.gz, optional `runs.db`, Cursor skills/rules/hooks | Per-host `SNAPSHOT_DIR` (NAS/disk), 30-day retain |
| 3 Host backup | Time Machine (both Macs); Fedora restic/Timeshift/whatever Travis already uses | Off-box |

Extend `agentic-os-dashboard/backup-scripts/brain-snapshot-backup.sh`:

- `OPENBRAIN_MODE=local` (default for Travis hosts): `podman exec $DB_CONTAINER pg_dump` on this machine
- `OPENBRAIN_MODE=ssh` keeps today’s hal9k remote path
- Refuse to treat LiveSync as the only backup
- Schedule snapshots **before** any blind home rsync
- Archives may contain `mcp.json`; document `chmod 700` on `SNAPSHOT_DIR`

Restore drill (must be in Travis-Fedora and both Mac docs):

1. Restore vault snapshot to a temp dir; confirm `thoughts.json` `thought_count`
2. Empty or new local `thoughts` table
3. `brain-sync pull` from the restored file (`OPEN_BRAIN_SYNC_JSON=` override)
4. `verify.sh` + `brain-sync status` (only-vault/only-local = 0 for that file)

## Health-check and brain checks

Portable script: `agentic-os-dashboard/scripts/health-check.sh`  
Compatibility: `health-check-travis.sh` execs it.

Host-specific sections via `AI_BRAIN_HOST`:

- All: paths, vault `hot.md` non-empty, Obsidian REST, Ollama, `nomic-embed-text`, Supabase REST, thoughts table, dashboard `EXECUTION_MODE=local`, `MEMORY_BACKEND=open-brain` ⇒ memory API **503 is pass**, MCP registrations, `KB_DIR` matches vault
- Apple + Intel: LaunchAgents (warn if skipped)
- Fedora: systemd `--user` units (warn if skipped)
- All: **`brain-sync status`** — fail if sync JSON is zero bytes; warn on only-vault / only-local / stale export
- Intel: warn if `git --version` < 2.42
- Apple: keep existing git PATH warning
- `my_ai_brain/scripts/verify.sh`: resolve repo via `MY_AI_BRAIN_REPO`, discover `supabase_db*`, no `$HOME/Github` hardcode
- `open-brain-preflight.mdc` unchanged in spirit; recovery commands must not hardcode Travis Apple container names
- `verify-brain-read-gate.sh` documented on all three hosts
- Cursor-os `health-check` skill Memory Layer: Open Brain REST is the pass condition when `MEMORY_BACKEND=open-brain`; SQLite 503 is expected, not a failure

## Scripts to add or rewrite (implementation later)

**`my_ai_brain`:**

| Path | Responsibility |
|------|----------------|
| `scripts/lib/thoughts_merge.py` | Pure merge + envelope validate (unit-tested) |
| `scripts/lib/load-ai-brain-env.sh` | Source config, discover DB container, set `LOG_DIR` |
| `scripts/brain-sync.sh` | `pull` / `push` / `status` |
| `scripts/install-ai-brain.sh` | New machine bootstrap |
| `scripts/backup.sh` | Wrapper: `brain-sync push` (keep name) |
| `scripts/restore.sh` | Wrapper: `brain-sync pull` |
| `scripts/verify.sh` | Path-agnostic verify |
| `scripts/ensure-ai-brain-services.sh` | No `_travis` / `Library/Logs` hardcodes; Fedora log path; discover Kong/DB names |
| `scripts/cursor-hook-backup.sh` | Call `brain-sync push` |
| `scripts/cursor-hook-ensure-services.sh` | Ensure then `brain-sync pull` |
| Host docs + MULTI-MACHINE + TROUBLESHOOTING | As named above |

**`agentic-os-dashboard`:**

| Path | Responsibility |
|------|----------------|
| `run-container-travis-mac-apple.sh` | Vault + `MEMORY_BACKEND` for Apple |
| `run-container-travis.sh` | `exec` alias to mac-apple |
| `run-container-travis-mac-intel.sh` | Intel vault placeholder + comments |
| `run-container-travis-fedora.sh` | Fedora vault + SELinux |
| `scripts/health-check.sh` | Portable health + sync drift |
| `scripts/health-check-travis.sh` | Alias |
| `backup-scripts/*` | `OPENBRAIN_MODE=local` |
| Host docs + PORTABLE-SETUP index | Travis-named files |

## Testing requirements

- Python unit tests for merge: only-local, only-vault, both with newer local, both with newer vault, equal timestamps (local wins), empty vault, invalid JSON, preserved UUIDs, `thought_count` mismatch rejected
- Shell smoke: `brain-sync status` with mocked dump is optional; do not require live Supabase in unit tests
- `verify.sh` must pass on Travis-Mac_Apple after implementation before documenting Intel/Fedora as ready

## Success criteria

1. Capturing on Apple in the morning and Fedora in the afternoon, with LiveSync in between, results in **both** IDs on **both** machines after pull — even if Fedora forgot to pull first, as long as Apple’s IDs were already in the vault file **or** Apple later pushes the union.
2. Empty/wiped `thoughts.json` never deletes local Postgres rows.
3. A new Travis-Mac-Intel or Travis-Fedora install can be completed from that host’s named docs without copying M3 absolute paths except as Apple examples.
4. Health-check on each host reports Open Brain + sync drift + brain-read-gate, using that host’s log/launch mechanism.

## Open values Travis fills at install time

- Travis-Mac-Intel vault absolute path
- Travis-Fedora home and vault absolute path (may be `/home/travis/...`)
- Whether Intel and Fedora install headless `agent-runner` (default: skip; Cursor MCP pickup)
- Snapshot `SNAPSHOT_DIR` per host
