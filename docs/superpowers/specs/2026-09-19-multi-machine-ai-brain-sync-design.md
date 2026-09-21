# Multi-machine AI Brain + Open Brain sync — Design Spec

**Date:** 2026-09-19  
**Amended:** 2026-09-20 — freeze Travis-Mac_Apple live entrypoints; Intel- and Fedora-specific scripts  
**Status:** Approved for planning; **not implemented**  
**Repos:** `my_ai_brain` (sync, Open Brain, host runbooks) and `agentic-os-dashboard` (host wrappers, health-check copies, snapshots)

## Goal

Run the same **offline-first** AI Brain stack on three Travis machines, without a shared remote Supabase, without losing thoughts when switching hosts during the day, and with documentation that is obviously Travis-owned.

Obsidian LiveSync already replicates the vault. Open Brain must use that same bus: a versioned JSON envelope in the vault, merged by thought UUID.

## Host names (locked)

Use these names in filenames, `MACHINE_LABEL`, wrappers, health-check output, and prose. Do not use generic labels like “other Mac” or “linux example.”

| Display name | `MACHINE_LABEL` / `AI_BRAIN_HOST` | Hardware | Role today |
|--------------|-----------------------------------|----------|------------|
| **Travis-Mac_Apple** | `travis-mac-apple` | Apple Silicon M3 (current daily driver) | **Frozen live stack.** Do not rewrite or alias its daily scripts. |
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

- `docs/TRAVIS-MAC-APPLE.md` — named front door; **keep** `docs/TRAVIS-MACOS-SETUP.md` as the operational runbook (do not stub or replace it)
- `docs/TRAVIS-MAC-INTEL.md`
- `docs/TRAVIS-FEDORA.md`
- Update `docs/PORTABLE-SETUP.md` to index the three Travis host docs first, then generic portable notes

Each host doc must say in the first paragraph which Travis machine it belongs to, the `MACHINE_LABEL`, and the sibling doc in the other repo.

## Non-goals (this project)

- Cloud-hosted Supabase or a single always-on Open Brain that secondaries dial into
- Syncing dashboard `runs.db`, `DASHBOARD_SECRET`, or per-instance `SUPABASE_SERVICE_ROLE_KEY`
- CRDT / per-thought files / multi-master conflict UI (out of scope until simultaneous capture actually loses data)
- Rewriting Travis-Mac_Apple live entrypoints (`ensure-ai-brain-services.sh`, `run-container-travis.sh`, `health-check-travis.sh`, `backup.sh`, `restore.sh`, `cursor-hook-ensure-services.sh`) to be “portable”
- Turning Apple scripts into aliases of a generic script
- Three copies of the UUID merge algorithm
- Implementing runtime scripts in the sessions that only produce or amend this spec

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

## Safer approach (locked 2026-09-20)

**Freeze Travis-Mac_Apple. Add host-specific Intel and Fedora scripts. Share only the merge library.**

| Layer | Apple (M3) | Intel / Fedora |
|-------|------------|----------------|
| Daily start, dashboard wrapper, health-check, sessionStart ensure | **Unchanged** existing files | **New** `*-travis-mac-intel` / `*-travis-fedora` scripts |
| UUID union-merge | Call shared `brain-sync.sh` **manually** (optional later hook) | Same shared `brain-sync.sh` from their start scripts |
| `backup.sh` / `restore.sh` | **Unchanged** (replace-dump; not on the daily path) | Do not use Apple dump/restore; use `brain-sync` only |

Rationale: Apple `ensure-ai-brain-services.sh` runs on every Cursor `sessionStart`. `run-container-travis.sh` and `health-check-travis.sh` are the daily dashboard path. Generalizing those is the break surface. Intel can clone Apple’s *flow* (Podman machine, LaunchAgents) with different paths; Fedora is a different script (native Podman, systemd, SELinux), not `if linux` inside Darwin scripts.

Do **not** triplicate `thoughts_merge.py` / `brain-sync.sh`. Three merge implementations is how thoughts get dropped.

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
- `~/.cursor/hooks/open-brain-backup.sh` still does a replace dump, but **`hooks.json` does not currently register a sessionEnd backup** on Travis-Mac_Apple. Do not wire Apple sessionEnd to dump-replace as part of this work.

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
5. Write **only** `open-brain-sync/thoughts.json`. Do **not** change Apple `backup.sh` to also write this file in v1. If Apple `backup.sh` still writes `open-brain-backup.json`, that is a separate legacy file — `brain-sync` must not read it as a v2 envelope (wrong schema / no stable UUID round-trip).

**Pull (`brain-sync pull`):**

1. If vault file missing, empty, or JSON invalid → **no-op** (do not truncate local DB). Warn. Exit 0 for hooks; exit 2 for interactive.
2. For each thought ID not in local DB: `INSERT` with the **same UUID**, then embed via local Ollama. Skip IDs already present (do not overwrite local content on pull; push already resolved conflicts by `updated_at`).
3. Do not dedupe by `content`. Two different IDs with similar text both stay.

**Status (`brain-sync status`):**

- Local count, vault count, IDs only-local, IDs only-vault, envelope `exported_at` age, envelope `machine`.
- Warn if vault file is older than 7 days or zero bytes.
- Warn if only-vault > 0 (you should pull) or only-local > 0 (you should push).

### Hook timing

| Event | Travis-Mac_Apple | Travis-Mac-Intel / Travis-Fedora |
|-------|------------------|----------------------------------|
| Daily start | Existing `~/start-ai-brain.sh` → existing `ensure-ai-brain-services.sh` (**no pull injected**) | New host start script: ensure-host then `brain-sync pull` |
| Cursor `sessionStart` | Existing `cursor-hook-ensure-services.sh` **unchanged** | Host-specific hook (new path in that machine’s `hooks.json` only) |
| Cursor `sessionEnd` | **Do not add** in v1 | Optional `brain-sync --hook push` on that host only |
| Manual | `brain-sync pull\|push\|status` (how Apple joins the sync file) | Same CLI |

Apple participates in union-merge by **manual** `brain-sync push` / `pull` until Travis opts into an extra Apple hook. That extra hook must be a **new file** (e.g. `cursor-hook-brain-sync.sh`) appended to Apple `hooks.json` — never by editing `cursor-hook-ensure-services.sh`.

Simultaneous capture on two machines the same minute can still race LiveSync on one file. Document: pull at session start; if `status` shows unexpected only-vault after a dual session, pull then push on the machine with the larger local count. Dated snapshots recover true loss.

### LiveSync wipe (known vault incident)

LiveSync has zeroed files (`hot.md`, repo profiles). Pull **must not** apply an empty envelope to Postgres. Push from a machine that still has rows rebuilds the JSON. Snapshots are the backup if every local DB is wrong.

## Machine configuration

Single sourced file: `~/.config/ai-brain/env` (mode `0600`). `scripts/lib/load-ai-brain-env.sh` also reads `~/.cursor/agentic-os.env` for dashboard overlap. Host values win over defaults.

**Hardcoded Apple paths stay in Apple-only scripts** (`ensure-ai-brain-services.sh`, `backup.sh`, `health-check-travis.sh`, `run-container-travis.sh`). New Intel/Fedora scripts and shared `brain-sync.sh` must not copy `MBP-M3-RH` / `supabase_db_travis` as required values. On Apple, `brain-sync.sh` may use `OBSIDIAN_VAULT_DIR` from existing `agentic-os.env` so `~/.config/ai-brain/env` is optional there.

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

Installer `scripts/install-ai-brain.sh` is for **Intel and Fedora** (and optional Apple env file only):

1. Require `--host=travis-mac-intel` or `travis-fedora` for full install. `--host=travis-mac-apple` may write `~/.config/ai-brain/env` with `--force` but **must not** retarget `~/start-ai-brain.sh` or `hooks.json`.
2. Prompt vault path; verify `hot.md` or `AI Brain/hot.md`.
3. Write `~/.config/ai-brain/env`.
4. `chmod 600` the env file.
5. `mkdir -p "$VAULT_DIR/open-brain-sync"`.
6. Symlink host start script: `~/start-ai-brain.sh` → `start-ai-brain-travis-mac-intel.sh` or `start-ai-brain-travis-fedora.sh` (**not** the Apple `start-ai-brain.sh` on those hosts).
7. `npm install` in `mcp-server`.
8. Print next step: `setup-cursor-bridge.sh --vault … --memory-backend open-brain --brain-read-gate`.

Intel Homebrew is `/usr/local`; Apple Silicon is `/opt/homebrew`. Ensure scripts prepend both. Fedora uses `/usr/bin` + `~/.local/bin`.

## Per-host stacks

### Travis-Mac_Apple (current) — frozen

Keep the live stack byte-for-byte unless Travis later asks to opt in:

- Vault: `/Users/travis/Documents/MBP-M3-RH/Obsidian-Work-Vault/Obsidian-Work`
- Repos: `/Users/travis/Github/{my_ai_brain,agentic-os-dashboard}`
- **Do not modify:** `run-container-travis.sh`, `scripts/health-check-travis.sh`, `scripts/ensure-ai-brain-services.sh`, `scripts/start-ai-brain.sh`, `scripts/backup.sh`, `scripts/restore.sh`, `scripts/cursor-hook-ensure-services.sh`, `scripts/verify.sh`
- LaunchAgents, sleepwatcher, `CURSOR_BRAIN_GATE_MODE=enforce` stay as today
- Operational dashboard runbook remains `docs/TRAVIS-MACOS-SETUP.md`; add `docs/TRAVIS-MAC-APPLE.md` as a named pointer only
- Sync: run `my_ai_brain/scripts/brain-sync.sh` manually (status / pull / push). First push gated on Travis watching LiveSync
- Optional later: new `cursor-hook-brain-sync.sh` in Apple `hooks.json` — separate change, not part of Intel/Fedora bootstrap

### Travis-Mac-Intel (new)

Same software as Apple, with these differences called out in `docs/hosts/TRAVIS-MAC-INTEL.md` and `agentic-os-dashboard/docs/TRAVIS-MAC-INTEL.md`:

- Homebrew prefix `/usr/local` (PATH, `flock`, sleepwatcher)
- `podman machine` required
- Vault path **unknown until install** — installer writes whatever LiveSync replica path Travis chooses; docs use `$VAULT_DIR` not a copied M3 path
- Stale Intel `/usr/local/bin/git` (2.23) **must** be called out: agent `--trailer` needs git ≥ 2.42 (already documented on Apple as a leftover Intel installer)
- headroom-ai: native x86_64 Python, not the Apple Silicon arm64 helper
- Own scripts (do not call Apple `ensure-ai-brain-services.sh` or `run-container-travis.sh`):
  - `my_ai_brain/scripts/ensure-ai-brain-services-travis-mac-intel.sh`
  - `my_ai_brain/scripts/start-ai-brain-travis-mac-intel.sh`
  - `my_ai_brain/scripts/verify-travis-mac-intel.sh`
  - `agentic-os-dashboard/run-container-travis-mac-intel.sh`
  - `agentic-os-dashboard/scripts/health-check-travis-mac-intel.sh`
- LaunchAgents yes; headless runner optional
- sleepwatcher: **copy** `install-sleepwatcher-wake.sh` pattern into an Intel installer or document running the existing installer with Intel log paths — do not change the Apple-installed `~/.wakeup` from Fedora/docs work
- Intel ensure script starts Podman machine, uses `/usr/local/bin` first, calls Intel dashboard wrapper, then `brain-sync pull`

### Travis-Fedora

Called **Travis-Fedora** everywhere (docs, units, comments). Differences:

- `dnf install podman nodejs npm jq util-linux`; Supabase CLI per my_ai_brain README
- **No** `podman machine`
- Volume `:z` SELinux on dashboard vault mount (existing `run-container.sh`)
- `scripts/install-agentic-os-systemd.sh` for dashboard/runner (runner optional)
- `LOG_DIR=$HOME/.local/state/ai-brain` — **never** `~/Library/Logs`
- No sleepwatcher; troubleshooting says Reload Cursor window after suspend
- Own scripts (never `~/Library/Logs`, never `podman machine`, never `launchctl`):
  - `my_ai_brain/scripts/ensure-ai-brain-services-travis-fedora.sh`
  - `my_ai_brain/scripts/start-ai-brain-travis-fedora.sh`
  - `my_ai_brain/scripts/verify-travis-fedora.sh`
  - `agentic-os-dashboard/run-container-travis-fedora.sh`
  - `agentic-os-dashboard/scripts/health-check-travis-fedora.sh`
- Health-check uses systemd `--user` status instead of `launchctl`
- Fedora ensure script starts native Podman containers, Intel/Apple LaunchAgent kickstart omitted, then `brain-sync pull`

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

**Travis-Mac_Apple:** keep `agentic-os-dashboard/scripts/health-check-travis.sh` and `my_ai_brain/scripts/verify.sh` unchanged. After `brain-sync` exists, Apple docs may say “also run `brain-sync status`” as an extra command — not a patch inside `health-check-travis.sh` in v1.

**Travis-Mac-Intel:** new `health-check-travis-mac-intel.sh` (copy Apple checklists, swap Homebrew `/usr/local`, git ≥ 2.42 warning, Intel wrapper name, `KB_DIR` still `/Users/...`). Include `brain-sync status`.

**Travis-Fedora:** new `health-check-travis-fedora.sh` (systemd `--user`, no LaunchAgents, `KB_DIR` `/home/...`, `LOG_DIR` Linux, SELinux). Include `brain-sync status`.

Do **not** introduce `health-check.sh` that Apple aliases to.

- Memory API: 503 remains **pass** for `MEMORY_BACKEND=open-brain` on all copies
- `open-brain-preflight.mdc` on Apple **unchanged**. Intel/Fedora get the same rule content via `setup-cursor-bridge.sh` with recovery commands that match *that* host (podman start vs no machine)
- `verify-brain-read-gate.sh` documented on all three hosts
- Do not `skill_patch` the live Apple health-check skill in v1 (avoid changing M3 agent behavior)

## Scripts to add (implementation later)

**Shared (`my_ai_brain`) — used by all hosts, additive:**

| Path | Responsibility |
|------|----------------|
| `scripts/lib/thoughts_merge.py` | Pure merge + envelope validate (unit-tested) |
| `scripts/lib/load-ai-brain-env.sh` | Source config; Apple can rely on `agentic-os.env` |
| `scripts/brain-sync.sh` | `pull` / `push` / `status` |
| `scripts/install-ai-brain.sh` | Intel/Fedora bootstrap (Apple env optional) |
| `scripts/cursor-hook-brain-sync.sh` | Optional later Apple/Intel/Fedora hook; **new file** |

**Travis-Mac_Intel only:**

| Path | Responsibility |
|------|----------------|
| `scripts/ensure-ai-brain-services-travis-mac-intel.sh` | Podman machine, `/usr/local`, Intel dashboard wrapper, then `brain-sync pull` |
| `scripts/start-ai-brain-travis-mac-intel.sh` | Wrapper |
| `scripts/verify-travis-mac-intel.sh` | Intel paths + shared merge import |
| `scripts/cursor-hook-ensure-services-travis-mac-intel.sh` | That host’s `hooks.json` only |

**Travis-Fedora only:**

| Path | Responsibility |
|------|----------------|
| `scripts/ensure-ai-brain-services-travis-fedora.sh` | Native Podman, systemd, Linux logs, then `brain-sync pull` |
| `scripts/start-ai-brain-travis-fedora.sh` | Wrapper |
| `scripts/verify-travis-fedora.sh` | Fedora paths |
| `scripts/cursor-hook-ensure-services-travis-fedora.sh` | That host’s `hooks.json` only |

**Do not modify in v1:** `ensure-ai-brain-services.sh`, `start-ai-brain.sh`, `backup.sh`, `restore.sh`, `verify.sh`, `cursor-hook-ensure-services.sh`, `cursor-hook-backup.sh`.

**`agentic-os-dashboard`:**

| Path | Responsibility |
|------|----------------|
| `run-container-travis.sh` | **Unchanged** (Apple) |
| `scripts/health-check-travis.sh` | **Unchanged** (Apple) |
| `run-container-travis-mac-intel.sh` | Intel vault + `MEMORY_BACKEND` |
| `run-container-travis-fedora.sh` | Fedora vault + SELinux |
| `scripts/health-check-travis-mac-intel.sh` | Intel health + `brain-sync status` |
| `scripts/health-check-travis-fedora.sh` | Fedora health + `brain-sync status` |
| `backup-scripts/*` | Additive `OPENBRAIN_MODE=local` (keep ssh default for hal9k) |
| Host docs + PORTABLE-SETUP index | Add Intel/Fedora + Apple named pointer; do not stub `TRAVIS-MACOS-SETUP.md` |

## Testing requirements

- Python unit tests for merge: only-local, only-vault, both with newer local, both with newer vault, equal timestamps (local wins), empty vault, invalid JSON, preserved UUIDs, `thought_count` mismatch rejected
- Shell smoke: `brain-sync status` with mocked dump is optional; do not require live Supabase in unit tests
- Apple `health-check-travis.sh` and `~/start-ai-brain.sh --check-only` must still pass **without** code changes to those files
- `brain-sync status` smoke on Apple after the shared CLI exists (manual; does not require hook changes)

## Success criteria

1. Capturing on Apple in the morning and Fedora in the afternoon, with LiveSync in between, results in **both** IDs on **both** machines after pull — even if Fedora forgot to pull first, as long as Apple’s IDs were already in the vault file **or** Apple later pushes the union.
2. Empty/wiped `thoughts.json` never deletes local Postgres rows.
3. A new Travis-Mac-Intel or Travis-Fedora install can be completed from that host’s named docs without copying M3 absolute paths except as Apple examples.
4. Intel and Fedora health-check scripts report Open Brain + sync drift + that host’s launch mechanism. Apple health-check remains the existing script; sync drift is a separate `brain-sync status` on Apple until an optional hook is added.
5. After implementation, grepping Apple live scripts shows **no** required edits from this project.

## Open values Travis fills at install time

- Travis-Mac-Intel vault absolute path
- Travis-Fedora home and vault absolute path (may be `/home/travis/...`)
- Whether Intel and Fedora install headless `agent-runner` (default: skip; Cursor MCP pickup)
- Snapshot `SNAPSHOT_DIR` per host
