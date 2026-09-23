# Travis-Fedora

Display name: **Travis-Fedora** (`travis-fedora`). Native Podman on Linux. Home directory is `/home/travis`.

**Install on this machine:** follow **[TRAVIS-FEDORA-QUICKSTART.md](TRAVIS-FEDORA-QUICKSTART.md)** (copy-paste steps, vault root, verify, first `brain-sync`).

This page is the path cheat-sheet. Sibling dashboard notes: `~/Github/agentic-os-dashboard/docs/TRAVIS-FEDORA.md`.

This machine runs its **own** Ollama + Supabase. Obsidian LiveSync already copies notes. Open Brain thoughts sync through `${VAULT_DIR}/open-brain-sync/thoughts.json` (UUID union-merge). Do **not** copy Apple’s `SUPABASE_SERVICE_ROLE_KEY` or `runs.db`.

Do **not** run Apple scripts here (`ensure-ai-brain-services.sh`, `start-ai-brain.sh`, `run-container-travis.sh`, `health-check-travis.sh`).

Sibling dashboard runbook: [`agentic-os-dashboard/docs/TRAVIS-FEDORA.md`](../../../agentic-os-dashboard/docs/TRAVIS-FEDORA.md) (same clone: `~/Github/agentic-os-dashboard/docs/TRAVIS-FEDORA.md`).

---

## Paths on this host

| Item | Path |
|------|------|
| Home | `/home/travis` |
| `my_ai_brain` | `/home/travis/Github/my_ai_brain` |
| `agentic-os-dashboard` | `/home/travis/Github/agentic-os-dashboard` |
| Logs | `~/.local/state/ai-brain` |
| Config | `~/.config/ai-brain/env` |
| Dashboard data | `~/.local/share/agentic-os-dashboard/` |
| Vault root | `/home/travis/Obsidian/obsidian-work/obsidian-work` |
| LAN IPv4 | `192.168.14.201` (observed 2026-09-21) |
| Supabase CLI | `2.117.0` (observed 2026-09-21) |

Open Brain on this host is **localhost only**: `http://127.0.0.1:54321` and `http://127.0.0.1:11434`. Do **not** point Apple Cursor at `192.168.14.201:54321`. After `run-container-travis-fedora.sh`, the dashboard is reachable from the LAN at `http://192.168.14.201:3888` (`DASHBOARD_BIND` defaults to `0.0.0.0`).

**Firewall:** Fedora firewalld blocks 3888 until you open it. For remote dashboard access:

```bash
sudo firewall-cmd --permanent --add-port=3888/tcp
sudo firewall-cmd --reload
```

Do **not** open Open Brain ports (`54321`, `11434`) on the LAN. Full note: `~/Github/agentic-os-dashboard/docs/TRAVIS-FEDORA.md`.

**Jira + Calendar** are not part of Open Brain. On Fedora they start unconfigured. Scaffold + fill per-host env (do not copy Apple files):

```bash
cd ~/Github/agentic-os-dashboard
./scripts/setup-jira-calendar-travis-fedora.sh
```

Details: dashboard `docs/TRAVIS-FEDORA.md` section **Jira + Google Calendar**.

LiveSync is **already working**. Same vault as Travis-Mac_Apple; only the host path differs:

| Host | Vault root |
|------|------------|
| Travis-Mac_Apple | `/Users/travis/Documents/MBP-M3-RH/Obsidian-Work-Vault/Obsidian-Work` |
| Travis-Fedora | `/home/travis/Obsidian/obsidian-work/obsidian-work` |

`Agentic OS Dashboard/` is a **folder inside** the vault (Mac: `…/Obsidian-Work/Agentic OS Dashboard`). Do **not** pass that nested path as `--vault` / `OBSIDIAN_VAULT_DIR` / `KB_DIR`. Those must be the vault root (`hot.md`, `AI Brain/`, `open-brain-sync/`).

Confirm: `ls /home/travis/Obsidian/obsidian-work/obsidian-work/hot.md`

---

## 0. Packages

```bash
sudo dnf install -y podman nodejs npm jq util-linux git python3 curl
git --version   # need >= 2.42 for agent --trailer
node --version  # 20+
```

**No** `podman machine`. Optional lingering so user systemd units survive logout:

```bash
loginctl enable-linger travis
```

Supabase CLI is not in Fedora’s default repos. Install one of:

```bash
# A) npm global
npm install -g supabase

# B) GitHub release binary into ~/.local/bin
# https://github.com/supabase/cli/releases
```

Confirm: `supabase --version`.

---

## 1. Repos (already cloned)

```text
/home/travis/Github/my_ai_brain
/home/travis/Github/agentic-os-dashboard
```

Checkout a branch that contains these Fedora scripts (`brain-sync.sh`, `*-travis-fedora.sh`, `run-container-travis-fedora.sh`).

---

## 2. Obsidian + LiveSync (already done)

Do **not** re-create the vault or re-pair LiveSync. Obsidian on Fedora already has the vault open.

Keep Local REST API enabled so Cursor MCP works (same plugin as Apple).

---

## 3. Write host env + start symlink

```bash
cd /home/travis/Github/my_ai_brain
chmod +x scripts/*.sh scripts/lib/*.sh 2>/dev/null || true

./scripts/install-ai-brain.sh --host=travis-fedora \
  --vault "/home/travis/Obsidian/obsidian-work/obsidian-work"
```

This writes `~/.config/ai-brain/env`, creates `open-brain-sync/` in the vault, `npm install`s `mcp-server`, and:

```text
~/start-ai-brain.sh  →  …/start-ai-brain-travis-fedora.sh
```

It does **not** write `mcp.json` keys.

---

## 4. First-time Open Brain (once)

Ollama container:

```bash
./scripts/bootstrap-open-brain-travis-fedora.sh
```

Local Supabase (new project on **this** host):

```bash
mkdir -p "$HOME/supabase-ai-brain" && cd "$HOME/supabase-ai-brain"
supabase init     # first time only
supabase start

DB=$(podman ps --filter name=supabase_db --format '{{.Names}}' | head -1)
KONG=$(podman ps --filter name=supabase_kong --format '{{.Names}}' | head -1)
podman exec -i "$DB" psql -U postgres < "$HOME/Github/my_ai_brain/sql/001-setup.sql"
podman exec "$KONG" cat /home/kong/kong.yml | grep sb_secret
```

Put **this** `sb_secret` into Fedora `~/.cursor/mcp.json` under `open-brain` (see `docs/cursor-mcp-config.json`). Point `command` at:

```text
/home/travis/Github/my_ai_brain/mcp-server/run-mcp.sh
```

Then:

```bash
cd /home/travis/Github/my_ai_brain/mcp-server
npm install
npm run build
```

`run-mcp.sh` looks for `/usr/bin/node` on Fedora.

---

## 5. Dashboard bridge + container

```bash
cd /home/travis/Github/agentic-os-dashboard

./scripts/setup-cursor-bridge.sh \
  --vault "/home/travis/Obsidian/obsidian-work/obsidian-work" \
  --memory-backend open-brain \
  --brain-read-gate

chmod +x run-container-travis-fedora.sh
./run-container-travis-fedora.sh
```

`run-container.sh` already uses SELinux `:z` on bind mounts. **Headless runner required** for UI/LAN RUNs (do not use `--dashboard-only`):

```bash
# CURSOR_API_KEY in ~/.cursor/agentic-os.env  OR  agent login
./scripts/install-agentic-os-systemd.sh --skip-skills
./scripts/check-agent-auth.sh
```

---

## 6. Cursor sessionStart hook

Point **Fedora** `~/.cursor/hooks.json` at the Fedora ensure script, **not** Apple `cursor-hook-ensure-services.sh`. Example command:

```json
"/home/travis/Github/my_ai_brain/scripts/cursor-hook-ensure-services-travis-fedora.sh"
```

Reload Cursor after `mcp.json` / hooks changes.

---

## 7. Verify

```bash
~/start-ai-brain.sh
cd /home/travis/Github/my_ai_brain && ./scripts/verify-travis-fedora.sh
cd /home/travis/Github/agentic-os-dashboard && ./scripts/health-check-travis-fedora.sh
```

`MEMORY_BACKEND=open-brain` is expected: dashboard `/api/memory/user-model` **503** is a **pass**. Prefer the **full** health check (not `--quick` alone) — `--quick` skips runner/auth and can look healthy while RUNs stick.

After sleep: **Reload Window** in Cursor (no sleepwatcher on Linux).

---

## 8. First thought sync

On Apple (when you are ready, watching LiveSync): `./scripts/brain-sync.sh push` so `open-brain-sync/thoughts.json` is non-zero.

On Fedora, after LiveSync downloads that file:

```bash
cd /home/travis/Github/my_ai_brain
./scripts/brain-sync.sh pull
./scripts/brain-sync.sh status
```

`only-vault` should go to 0. Capture a test thought, then:

```bash
./scripts/brain-sync.sh push
```

If `thoughts.json` is **0 bytes**, do **not** pull. Push from a host that still has rows (usually Apple).

`~/start-ai-brain.sh` already runs `brain-sync pull` after services are up.

---

## Daily

Always-on Mac + Fedora: **[DAILY-CHECKLIST.md](DAILY-CHECKLIST.md)**.

| When | Command |
|------|---------|
| Leaving Fedora | `~/Github/my_ai_brain/scripts/brain-sync.sh push` |
| Arriving | Wait for LiveSync, then `brain-sync.sh pull` and `status` |
| After reboot only | `~/start-ai-brain.sh` |
| Health (if something is down) | `~/Github/agentic-os-dashboard/scripts/health-check-travis-fedora.sh` (full check) |

Apple `backup.sh` is a **legacy dump** — do not use it as the multi-machine sync on Fedora.
