# Host install checklist (Travis-Mac_Apple / Intel / Fedora)

**Date:** 2026-09-20  
**Depends on:** spec `2026-09-19-multi-machine-ai-brain-sync-design.md` (amended freeze-Apple)  
**Status:** The Intel/Fedora scripts and `brain-sync.sh` are **not built yet**. Phase 0 must finish before Phases 1–3 are runnable as written.

Each machine runs its **own** Ollama + Supabase. Obsidian LiveSync already copies notes. Open Brain thoughts ride `open-brain-sync/thoughts.json` via UUID union-merge (`brain-sync`). Dashboard queues and Supabase keys stay **local**.

---

## Phase 0 — Once, before any new machine (build the tooling)

On whatever clone you use to implement (this can be Travis-Mac_Apple git, without changing live Apple start scripts):

1. Implement the plan: shared `thoughts_merge.py` + `brain-sync.sh`, plus Intel/Fedora named scripts (do **not** rewrite Apple `ensure` / `run-container-travis.sh` / `health-check-travis.sh`).
2. Merge/push those repos when you are ready (`my_ai_brain`, `agentic-os-dashboard`).
3. On Apple, confirm the frozen stack still works: `~/start-ai-brain.sh --check-only` and `./scripts/health-check-travis.sh --quick`.

---

## Phase 1 — Travis-Mac_Apple (M3, already running)

You do **not** reinstall Open Brain, the dashboard, LaunchAgents, sleepwatcher, or the vault. Daily commands stay the same.

**One-time (after Phase 0):**

1. Optional: `mkdir -p "$VAULT_DIR/open-brain-sync"` (vault is `/Users/travis/Documents/MBP-M3-RH/Obsidian-Work-Vault/Obsidian-Work`).
2. Take a dated snapshot or Time Machine backup of the vault **and** a `pg_dump` of local thoughts (safety before first sync file).
3. With LiveSync idle and you watching:  
   `cd ~/Github/my_ai_brain && ./scripts/brain-sync.sh status`  
   then, only when you confirm: `./scripts/brain-sync.sh push`  
   Confirm `open-brain-sync/thoughts.json` appears in the vault and LiveSync uploads it (non-zero size).
4. Do **not** change `~/.cursor/hooks.json`, `~/start-ai-brain.sh`, or `run-container-travis.sh`.

**Ongoing on Apple (v1):**

- Capture as today.
- Before you leave this Mac for Intel/Fedora for a while: `./scripts/brain-sync.sh push`.
- When you return: wait for LiveSync, then `./scripts/brain-sync.sh pull` then `status` (`only-vault` should be 0).
- Optional later (not required to stand up the other machines): add the **new** `cursor-hook-brain-sync.sh` to Apple hooks — a separate decision.

**Do not:** run `install-ai-brain.sh --host=travis-mac-intel` on this Mac; do not point Apple Cursor at another machine’s Supabase; do not use `backup.sh` as the multi-machine sync (legacy dump).

---

## Phase 2 — Travis-Mac-Intel (new)

Prereqs: Obsidian vault already LiveSync’d to a local path; git clones of `my_ai_brain` and `agentic-os-dashboard` on a branch that contains Phase 0.

1. Install Homebrew, Podman, Node 20+, `jq`, `flock` (`brew install util-linux`), Supabase CLI.
2. `podman machine init && podman machine start`.
3. Confirm `git --version` is **≥ 2.42**. If `/usr/local/bin/git` is old Intel git-scm, remove those stale symlinks (same class of bug as on Apple).
4. Clone repos (paths may differ from `/Users/travis/Github/...` — record them).
5. Open Obsidian on the LiveSync vault; enable Local REST API.
6. `cd my_ai_brain && ./scripts/install-ai-brain.sh --host=travis-mac-intel --vault "/actual/intel/vault/path"`  
   This writes `~/.config/ai-brain/env` and should symlink `~/start-ai-brain.sh` to **`start-ai-brain-travis-mac-intel.sh`**, not the Apple script.
7. First-time Open Brain: start Ollama container, `ollama pull nomic-embed-text`, `supabase start` (or follow `docs/hosts/TRAVIS-MAC-INTEL.md`), apply `sql/001-setup.sql`, put **this machine’s** service-role key in `~/.cursor/mcp.json` via `run-mcp.sh` (do not copy Apple’s key).
8. Dashboard:  
   `cd agentic-os-dashboard && ./scripts/setup-cursor-bridge.sh --vault "<same vault>" --memory-backend open-brain --brain-read-gate`  
   Set `OBSIDIAN_VAULT_DIR` in `run-container-travis-mac-intel.sh` (or env), then run that wrapper — **not** `run-container-travis.sh`.
9. Optional: LaunchAgents, `agent login`, sleepwatcher (Intel Homebrew `/usr/local`). Headless runner is optional; Cursor chat pickup is enough.
10. Reload Cursor. Run `./scripts/health-check-travis-mac-intel.sh --quick` and `~/start-ai-brain.sh` (Intel script).
11. Wait until LiveSync has `open-brain-sync/thoughts.json` from Apple, then `./scripts/brain-sync.sh pull` and `status`.
12. Capture a test thought, `brain-sync push`, confirm Apple can `pull` it later.

---

## Phase 3 — Travis-Fedora (new)

Same idea as Intel, different OS plumbing.

1. `sudo dnf install -y podman nodejs npm jq util-linux`; install Supabase CLI per `my_ai_brain` README. **No** `podman machine`.
2. Clone both repos; confirm vault LiveSync path (often `/home/travis/...` — use the real path).
3. `./scripts/install-ai-brain.sh --host=travis-fedora --vault "/actual/fedora/vault/path"`  
   Symlink `~/start-ai-brain.sh` → **`start-ai-brain-travis-fedora.sh`**. `LOG_DIR` must be `~/.local/state/ai-brain`, not `~/Library/Logs`.
4. Start Ollama + Supabase locally; apply schema; **new** service-role key in Fedora `~/.cursor/mcp.json`.
5. `setup-cursor-bridge.sh --vault "<fedora vault>" --memory-backend open-brain --brain-read-gate`.
6. Fill vault path in `run-container-travis-fedora.sh`; run it (SELinux `:z` on the mount). Optional: `./scripts/install-agentic-os-systemd.sh` (runner optional).
7. Point Fedora `hooks.json` at **`cursor-hook-ensure-services-travis-fedora.sh`**, not the Apple hook path.
8. Reload Cursor. `./scripts/health-check-travis-fedora.sh --quick`. No sleepwatcher; after suspend, Reload Window.
9. LiveSync → `brain-sync pull` → `status` → test capture → `push`.

---

## After all three exist — switching machines

| When | Do |
|------|----|
| Leaving a machine | `brain-sync push` (Apple: manual. Intel/Fedora: start script already pulls; push if you captured.) |
| Arriving | Wait for LiveSync; `brain-sync pull`; `status` |
| `thoughts.json` is 0 bytes | Do **not** pull; push from a host that still has rows (usually Apple) |
| Same day, two machines | Rare race on one JSON file; pull then push on the host with more local thoughts |

---

## Values you fill at install time

- Travis-Mac-Intel vault absolute path  
- Travis-Fedora home + vault absolute path  
- Whether Intel/Fedora get headless `agent-runner` (default: skip)  
- Snapshot `SNAPSHOT_DIR` if you enable dated backups  
