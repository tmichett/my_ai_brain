# Travis-Fedora installation quickstart

Follow this document **on the Fedora machine** (`travis-fedora`). Home is `/home/travis`. Apple Silicon (`travis-mac-apple`) keeps its frozen start scripts; do not run those here.

**Goal:** local Ollama + Supabase (Open Brain) + Agentic OS Dashboard, Cursor MCP, and UUID union-merge of thoughts via LiveSync. Notes already replicate. Thoughts do **not** until `brain-sync`.

Related: [TRAVIS-FEDORA.md](TRAVIS-FEDORA.md) (path cheat-sheet) · [MULTI-MACHINE.md](../MULTI-MACHINE.md) · [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) · dashboard [TRAVIS-FEDORA.md](../../../agentic-os-dashboard/docs/TRAVIS-FEDORA.md)

---

## Already done (skip)

| Item | Status |
|------|--------|
| Obsidian vault + LiveSync | **Working.** Do not re-pair or copy the vault. |
| Git clones | `/home/travis/Github/my_ai_brain` and `/home/travis/Github/agentic-os-dashboard` |

You still need the **Fedora-first scripts** in those clones (`brain-sync.sh`, `*-travis-fedora.sh`, `run-container-travis-fedora.sh`). If Fedora `git status` does not show them, pull/copy the working tree from the Mac after those files exist on a branch.

---

## Do not

- Do **not** run Apple scripts: `ensure-ai-brain-services.sh`, Apple `start-ai-brain.sh`, `run-container-travis.sh`, `health-check-travis.sh`, `cursor-hook-ensure-services.sh`.
- Do **not** copy Apple’s `SUPABASE_SERVICE_ROLE_KEY`, dashboard `secret`, `runs.db`, `jira.env`, `google-calendar.env`, or Google Calendar token JSON.
- Do **not** use `backup.sh` / `restore.sh` as the multi-machine sync.
- Do **not** pass the nested notebook folder as `--vault`:

```text
WRONG  /home/travis/Obsidian/obsidian-work/obsidian-work/Agentic OS Dashboard
RIGHT  /home/travis/Obsidian/obsidian-work/obsidian-work
```

That nested folder is the same notebook as Mac  
`/Users/travis/Documents/MBP-M3-RH/Obsidian-Work-Vault/Obsidian-Work/Agentic OS Dashboard`.  
`--vault`, `OBSIDIAN_VAULT_DIR`, and `KB_DIR` must be the **vault root** (`hot.md`, `AI Brain/`, later `open-brain-sync/`).

- Do **not** `brain-sync pull` if `open-brain-sync/thoughts.json` is missing or **0 bytes**.

---

## What runs where

```text
Cursor (Fedora)
  ├── Obsidian MCP  →  local Obsidian app  →  LiveSync vault (notes already sync)
  ├── Open Brain MCP →  Ollama :11434  +  this host’s Supabase :54321
  └── Dashboard MCP  →  Podman agentic-os-dashboard :3888

LiveSync copies markdown, including open-brain-sync/thoughts.json once it exists.
brain-sync.sh merges thought UUIDs. Embeddings are rebuilt on pull. Keys stay local.
```

| Port | Service |
|------|---------|
| `11434` | Ollama (`nomic-embed-text`, 768d) |
| `54321` | This machine’s Supabase REST (Kong) |
| `3888` | Agentic OS Dashboard |
| `27124` | Obsidian Local REST API (app must be open) |

**No** `podman machine` (that is macOS). Native Podman. SELinux `:z` is already in `run-container.sh`.

---

## Paths

| Item | Path |
|------|------|
| Home | `/home/travis` |
| Vault root | `/home/travis/Obsidian/obsidian-work/obsidian-work` |
| Mac vault (same LiveSync) | `/Users/travis/Documents/MBP-M3-RH/Obsidian-Work-Vault/Obsidian-Work` |
| `my_ai_brain` | `/home/travis/Github/my_ai_brain` |
| `agentic-os-dashboard` | `/home/travis/Github/agentic-os-dashboard` |
| Host env | `~/.config/ai-brain/env` |
| Logs | `~/.local/state/ai-brain` |
| Dashboard data | `~/.local/share/agentic-os-dashboard/` |
| Start symlink | `~/start-ai-brain.sh` → `…/start-ai-brain-travis-fedora.sh` |

Confirm the vault root before anything else:

```bash
ls -l /home/travis/Obsidian/obsidian-work/obsidian-work/hot.md
ls -d "/home/travis/Obsidian/obsidian-work/obsidian-work/AI Brain"
ls -d "/home/travis/Obsidian/obsidian-work/obsidian-work/Agentic OS Dashboard"
```

The third path is a **child** of the vault, not the vault.

---

## Step 1 — Packages

```bash
sudo dnf install -y podman nodejs npm jq util-linux git python3 curl openssl
git --version    # need >= 2.42 (agent --trailer)
node --version   # 20+
podman --version
```

Optional (only if you later install user systemd units and want them after logout):

```bash
loginctl enable-linger travis
```

Supabase CLI is not in default Fedora repos:

```bash
npm install -g supabase
supabase --version
```

Observed on this host 2026-09-21: **2.117.0**. Any current 2.x CLI is fine for local `supabase start`.

Alternatively install a release binary into `~/.local/bin` from https://github.com/supabase/cli/releases.

---

## Step 2 — Host env + start symlink

```bash
cd /home/travis/Github/my_ai_brain
chmod +x scripts/*.sh scripts/lib/*.sh mcp-server/run-mcp.sh 2>/dev/null || true

test -x scripts/install-ai-brain.sh \
  && test -x scripts/brain-sync.sh \
  && test -x scripts/ensure-ai-brain-services-travis-fedora.sh \
  || { echo "Fedora scripts missing — pull/copy the Fedora-first tree first"; exit 1; }

./scripts/install-ai-brain.sh --host=travis-fedora \
  --vault "/home/travis/Obsidian/obsidian-work/obsidian-work"
```

That command:

- writes `~/.config/ai-brain/env` (mode `600`)
- creates `$VAULT/open-brain-sync/`
- `npm install`s `mcp-server`
- symlinks `~/start-ai-brain.sh` → `start-ai-brain-travis-fedora.sh`

It does **not** write `~/.cursor/mcp.json` keys.

If you accidentally pass `…/Agentic OS Dashboard`, the installer refuses.

---

## Step 3 — Ollama (once)

```bash
cd /home/travis/Github/my_ai_brain
./scripts/bootstrap-open-brain-travis-fedora.sh
curl -sf http://127.0.0.1:11434/api/tags | python3 -c \
  "import json,sys; m=[x['name'] for x in json.load(sys.stdin).get('models',[])]; assert any('nomic-embed' in x for x in m); print('ok', m)"
```

Later boots: `podman start ollama` (or `~/start-ai-brain.sh`).

---

## Step 4 — Local Supabase (once, this host only)

New project. New service-role key. **Never** reuse Apple’s `sb_secret`.

```bash
mkdir -p "$HOME/supabase-ai-brain"
cd "$HOME/supabase-ai-brain"
supabase init      # first time only
supabase start
```

Wait until Kong is up, then apply schema and copy **this host’s** Secret into Fedora `~/.cursor/mcp.json` only.

```bash
DB=$(podman ps --filter name=supabase_db --format '{{.Names}}' | head -1)
KONG=$(podman ps --filter name=supabase_kong --format '{{.Names}}' | head -1)
echo "DB=$DB  KONG=$KONG"
podman exec -i "$DB" psql -U postgres < /home/travis/Github/my_ai_brain/sql/001-setup.sql
```

Read the Secret from the `supabase start` table or Kong, then put it in `mcp.json`. **Never paste that table into a GitHub issue/PR** — `tmichett/my_ai_brain` is public; GitHub secret scanning flags `sb_secret_…` (see issue #3). Local CLI often prints the same default JWT as other machines; that is still not for GitHub.

> **GitHub:** do not `grep sb_secret` into a ticket. Keep keys in `~/.cursor/mcp.json` (mode 600).

Container names will **not** be `supabase_db_travis` (that is Apple). Fedora scripts discover `supabase_db*` / `supabase_kong*`.

Smoke:

```bash
curl -sf http://127.0.0.1:54321/rest/v1/ -H "apikey: placeholder" -o /dev/null && echo "kong:ok"
```

---

## Step 5 — Build Open Brain MCP + `mcp.json`

```bash
cd /home/travis/Github/my_ai_brain/mcp-server
npm install
npm run build
test -x /usr/bin/node && /usr/bin/node --version
test -f dist/index.js
```

In **Fedora** `~/.cursor/mcp.json`, under `mcpServers`, set `open-brain` to **this host’s** key and Linux paths. Shape (do not paste Apple’s secret):

```json
"open-brain": {
  "command": "/home/travis/Github/my_ai_brain/mcp-server/run-mcp.sh",
  "args": [],
  "env": {
    "SUPABASE_URL": "http://127.0.0.1:54321",
    "SUPABASE_SERVICE_ROLE_KEY": "<paste THIS host's sb_secret>",
    "OLLAMA_URL": "http://127.0.0.1:11434",
    "OLLAMA_EMBED_MODEL": "nomic-embed-text"
  }
}
```

`run-mcp.sh` prefers `/usr/bin/node` after Homebrew paths (Fedora `dnf` Node). Cursor MCP does not load your shell `PATH`.

Keep Obsidian open with **Local REST API** enabled (already used for LiveSync-era MCP). `setup-cursor-bridge.sh` in the next step registers dashboard MCP; you merge `open-brain` as above if the bridge does not.

---

## Step 6 — Dashboard bridge + container

```bash
cd /home/travis/Github/agentic-os-dashboard
chmod +x run-container-travis-fedora.sh scripts/health-check-travis-fedora.sh

./scripts/setup-cursor-bridge.sh \
  --vault "/home/travis/Obsidian/obsidian-work/obsidian-work" \
  --memory-backend open-brain \
  --brain-read-gate

./run-container-travis-fedora.sh
```

`MEMORY_BACKEND=open-brain` is required. Dashboard `/api/memory/user-model` returning **HTTP 503** is a **pass** (memory lives in Open Brain, not SQLite).

Optional headless runner (skip if you pick up dashboard prompts in Cursor chat):

```bash
./scripts/install-agentic-os-systemd.sh --dashboard-only --skip-skills
```

Do **not** run `./run-container-travis.sh` on Fedora.

Confirm the container can read vault root (not the nested folder):

```bash
podman exec agentic-os-dashboard test -r /data/vault/hot.md && echo "vault mount:ok"
```

**LAN / remote UI:** firewalld must allow **TCP 3888** or other machines cannot reach `http://192.168.14.201:3888`. Local Cursor still uses `127.0.0.1:3888`.

```bash
sudo firewall-cmd --permanent --add-port=3888/tcp
sudo firewall-cmd --reload
```

Do **not** open `54321` / `11434` for LAN. Details: dashboard `docs/TRAVIS-FEDORA.md`.

---

## Step 6b — Jira + Google Calendar (dashboard)

Open Brain can be healthy while **`/jira` and `/calendar` are still empty** on Fedora. Those use **per-host** files. Do not scp Apple’s copies.

```bash
cd /home/travis/Github/agentic-os-dashboard
chmod +x scripts/setup-jira-calendar-travis-fedora.sh
./scripts/setup-jira-calendar-travis-fedora.sh
```

Edit `~/.local/share/agentic-os-dashboard/jira.env` (Atlassian URL, email, API token — type the same token as Apple) and `google-calendar.env` (OAuth client). On the Google Cloud OAuth client, add redirect URIs for both localhost and LAN:

```
http://localhost:3888/api/calendar/oauth/callback
http://192.168.14.201:3888/api/calendar/oauth/callback
```

Set `GOOGLE_REDIRECT_URI` to the URL you will actually open when clicking **Connect**. Recreate the container, then open `/jira` and `/calendar` → Connect (or Reconnect for write). Full note: dashboard [TRAVIS-FEDORA.md](../../../agentic-os-dashboard/docs/TRAVIS-FEDORA.md).

Cursor `jira-mcp` is optional and separate; dashboard `/jira` does not need it.

---

## Step 7 — Fedora sessionStart hook

Apple `hooks.json` points at `cursor-hook-ensure-services.sh`. On Fedora, that line must be the **Fedora** hook.

Edit `~/.cursor/hooks.json` `sessionStart` so the ensure entry is:

```json
{
  "command": "bash $HOME/Github/my_ai_brain/scripts/cursor-hook-ensure-services-travis-fedora.sh",
  "timeout": 15
}
```

Leave other hooks that `setup-cursor-bridge.sh` installed (`agentic-os-check-dashboard.sh`, `memory-load.sh`, brain-read, etc.). Do not point Fedora Cursor at the Apple ensure script.

---

## Step 8 — Reload Cursor and verify

1. Keep **Obsidian** open (Local REST API).
2. **Reload Window** in Cursor (`Ctrl+Shift+P` → Reload Window).
3. Confirm MCP: `open-brain`, `obsidian`, `agentic-os-dashboard` green.

```bash
~/start-ai-brain.sh
~/start-ai-brain.sh --check-only

cd /home/travis/Github/my_ai_brain
./scripts/verify-travis-fedora.sh

cd /home/travis/Github/agentic-os-dashboard
./scripts/health-check-travis-fedora.sh --quick
```

Open http://127.0.0.1:3888 (token is local `~/.local/share/agentic-os-dashboard/secret`).

After suspend/resume: **Reload Window** again (no sleepwatcher on Linux).

---

## Step 9 — First Open Brain thought sync

LiveSync will copy `open-brain-sync/thoughts.json` once it exists. Fedora `~/start-ai-brain.sh` already runs `brain-sync pull` after services are up.

**On Apple** (when you are watching LiveSync, vault idle):

```bash
cd ~/Github/my_ai_brain
./scripts/brain-sync.sh status
./scripts/brain-sync.sh push
ls -l "/Users/travis/Documents/MBP-M3-RH/Obsidian-Work-Vault/Obsidian-Work/open-brain-sync/thoughts.json"
```

File must be **non-zero**. Wait until Fedora LiveSync has the same file.

**On Fedora:**

```bash
ls -l /home/travis/Obsidian/obsidian-work/obsidian-work/open-brain-sync/thoughts.json
# if size is 0, STOP — do not pull

cd /home/travis/Github/my_ai_brain
./scripts/brain-sync.sh pull
./scripts/brain-sync.sh status
```

`only-vault` should go to `0`. Capture a test thought in Cursor, then:

```bash
./scripts/brain-sync.sh push
```

Later, Apple `brain-sync pull` should pick that UUID up.

---

## Daily (Fedora)

Always-on Mac + Fedora (Cursor/Obsidian stay up): **[DAILY-CHECKLIST.md](DAILY-CHECKLIST.md)**.

| When | Command |
|------|---------|
| Leaving Fedora | `~/Github/my_ai_brain/scripts/brain-sync.sh push` |
| Arriving | Wait for LiveSync, then `brain-sync.sh pull` and `status` |
| After reboot only | `~/start-ai-brain.sh` |
| Health (if something is down) | `~/Github/agentic-os-dashboard/scripts/health-check-travis-fedora.sh --quick` |

---

## Success checklist

- [ ] `ls …/obsidian-work/obsidian-work/hot.md` works
- [ ] `~/start-ai-brain.sh --check-only` exits 0
- [ ] `verify-travis-fedora.sh` all OK
- [ ] `health-check-travis-fedora.sh --quick` healthy (memory API **503** is OK)
- [ ] Cursor MCP: open-brain / obsidian / dashboard green
- [ ] `podman exec agentic-os-dashboard test -r /data/vault/hot.md`
- [ ] `thoughts.json` non-zero after Apple push; Fedora `brain-sync status` `only-vault=0`

---

## Troubleshooting (short)

| Symptom | Fix |
|---------|-----|
| Installer rejects vault | You passed `Agentic OS Dashboard/`. Use the vault **root**. |
| `ollama` missing | `./scripts/bootstrap-open-brain-travis-fedora.sh` |
| No `supabase_*` containers | `cd ~/supabase-ai-brain && supabase start` |
| Open Brain MCP red | `npm run build` in `mcp-server`; `/usr/bin/node`; **this** host’s `sb_secret`; Reload Window |
| Dashboard cannot read `hot.md` | Recreate with `./run-container-travis-fedora.sh` (SELinux `:z`) |
| LAN browser cannot open `:3888` | `sudo firewall-cmd --permanent --add-port=3888/tcp && sudo firewall-cmd --reload` (do not open Open Brain ports) |
| `/jira` setup banner / `/calendar` never Connects | Per-host env missing. `./scripts/setup-jira-calendar-travis-fedora.sh`, fill tokens, recreate container. Do not copy Apple’s env files. |
| `thoughts.json` is 0 bytes | Do **not** pull. Push from a host that still has rows (usually Apple) |
| After sleep, MCP red | Reload Window |

More: [TROUBLESHOOTING.md](../TROUBLESHOOTING.md)
