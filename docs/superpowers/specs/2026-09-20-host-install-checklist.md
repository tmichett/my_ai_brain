# Host install checklist (Travis-Mac_Apple / Intel / Fedora)

**Date:** 2026-09-20  
**Depends on:** spec `2026-09-19-multi-machine-ai-brain-sync-design.md` (amended freeze-Apple)  
**Status:** Fedora-first drop is in the working trees: shared `brain-sync.sh` + Travis-Fedora named scripts. Intel scripts are **not** in this drop. Apple live entrypoints are still frozen.

Each machine runs its **own** Ollama + Supabase. Obsidian LiveSync already copies notes. Open Brain thoughts ride `open-brain-sync/thoughts.json` via UUID union-merge (`brain-sync`). Dashboard queues and Supabase keys stay **local**.

---

## Phase 0 — Once, before any new machine (build the tooling)

On whatever clone you use to implement (this can be Travis-Mac_Apple git, without changing live Apple start scripts):

1. ~~Implement Fedora-first tooling~~ (in tree, uncommitted until you push): `thoughts_merge.py` + `brain-sync.sh` + Travis-Fedora named scripts. Apple `ensure` / `run-container-travis.sh` / `health-check-travis.sh` were not rewritten.
2. Merge/push those repos when you are ready (`my_ai_brain`, `agentic-os-dashboard`) so Fedora can `git pull`.
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

**Full steps:** [docs/hosts/TRAVIS-FEDORA-QUICKSTART.md](../../hosts/TRAVIS-FEDORA-QUICKSTART.md) (this repo) and `agentic-os-dashboard/docs/TRAVIS-FEDORA.md`.

Home `/home/travis`; clones `/home/travis/Github/{my_ai_brain,agentic-os-dashboard}`. LiveSync vault is **already working**. Vault root: `/home/travis/Obsidian/obsidian-work/obsidian-work` (not the nested `Agentic OS Dashboard/` folder).

1. `sudo dnf install -y podman nodejs npm jq util-linux git python3 curl`. **No** `podman machine`.
2. `git pull` (or copy) a tree that contains the Fedora scripts.
3. `./scripts/install-ai-brain.sh --host=travis-fedora --vault "/home/travis/Obsidian/obsidian-work/obsidian-work"`
4. `./scripts/bootstrap-open-brain-travis-fedora.sh` then local `supabase start` + `sql/001-setup.sql` + **this host’s** key in `mcp.json`.
5. Dashboard: `setup-cursor-bridge.sh --vault … --memory-backend open-brain --brain-read-gate` then `./run-container-travis-fedora.sh`.
6. Fedora `hooks.json` → `cursor-hook-ensure-services-travis-fedora.sh`. Reload Cursor. `health-check-travis-fedora.sh --quick`.
7. LiveSync → `brain-sync pull` → `status` → test capture → `push`.

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

- Travis-Mac-Intel vault absolute path (still unknown)
- Travis-Fedora vault root: `/home/travis/Obsidian/obsidian-work/obsidian-work` (LiveSync already working; home `/home/travis`)
- Whether Intel/Fedora get headless `agent-runner` (default: skip)
- Snapshot `SNAPSHOT_DIR` if you enable dated backups  
