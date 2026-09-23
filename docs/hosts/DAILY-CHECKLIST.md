# Daily checklist — Travis-Mac_Apple + Travis-Fedora

Always-on desk switch. **Cursor, Obsidian, Podman (Ollama / Supabase / dashboard) stay running** on both machines. You do **not** quit Cursor or restart the stack when you walk to the other desk.

Install and first-time sync: [TRAVIS-FEDORA-QUICKSTART.md](TRAVIS-FEDORA-QUICKSTART.md). Architecture: [MULTI-MACHINE.md](../MULTI-MACHINE.md).

---

## What is already handled

| Already running | What it does | What it does **not** do |
|-----------------|--------------|-------------------------|
| **Obsidian** (both hosts) | LiveSync copies **notes** and `open-brain-sync/thoughts.json` | Merge thoughts into this host’s Postgres |
| **Cursor** | Agents, MCP, dashboard pickup in **new chats** | `brain-sync` |
| **Dashboard + Open Brain containers** | Local UI + this host’s thought DB | Copy rows to the other machine |

Notes follow you automatically (LiveSync). **Open Brain does not**, until you `pull` / `push` on the machine you are sitting at.

Apple `~/start-ai-brain.sh` never pulls (frozen). Fedora start **does** pull, but that only runs after reboot — skip it on a normal switch.

---

## Paths

| | Travis-Mac_Apple | Travis-Fedora |
|--|------------------|---------------|
| Vault root | `/Users/travis/Documents/MBP-M3-RH/Obsidian-Work-Vault/Obsidian-Work` | `/home/travis/Obsidian/obsidian-work/obsidian-work` |
| Repo | `~/Github/my_ai_brain` | `/home/travis/Github/my_ai_brain` |
| Sync file | `…/open-brain-sync/thoughts.json` | same folder under vault root |
| Dashboard | http://127.0.0.1:3888 | http://127.0.0.1:3888 (LAN: `http://192.168.14.201:3888`) |

`thoughts.json` must be **non-zero**. If it is **0 bytes** or missing: **do not pull**. Push from the host that still has thoughts (usually the Mac).

---

## Leave this desk (push)

Do this on the machine you **just used**, before you walk away — even if Cursor stays open.

### Travis-Mac_Apple

- [ ] Obsidian still open (LiveSync keeps running after you leave)
- [ ] If you (or an agent) captured Open Brain thoughts this session:

```bash
cd ~/Github/my_ai_brain
./scripts/brain-sync.sh status
./scripts/brain-sync.sh push
ls -l "/Users/travis/Documents/MBP-M3-RH/Obsidian-Work-Vault/Obsidian-Work/open-brain-sync/thoughts.json"
```

- [ ] File size is **> 0**. Leave Obsidian open so LiveSync can send it to Fedora.
- [ ] Leave Cursor and the dashboard running. No quit, no container stop.

### Travis-Fedora

- [ ] Obsidian still open
- [ ] If Open Brain was used this session:

```bash
cd /home/travis/Github/my_ai_brain
./scripts/brain-sync.sh status
./scripts/brain-sync.sh push
ls -l /home/travis/Obsidian/obsidian-work/obsidian-work/open-brain-sync/thoughts.json
```

- [ ] File size is **> 0**. Leave Obsidian open.
- [ ] Leave Cursor and the dashboard running.

Skip **push** only if you are sure nothing new went into Open Brain (notes-only, no `capture_thought`). When unsure, push — union-merge is safe.

---

## Sit down at the other desk (pull)

Do this on the machine you **just sat down at**. Do not restart Cursor first.

### Both hosts (same steps)

- [ ] Obsidian is open (already). Wait until LiveSync has the **other** host’s `thoughts.json` (size matches, not 0 bytes).
- [ ] Merge into **this** host’s database:

**Mac**

```bash
cd ~/Github/my_ai_brain
./scripts/brain-sync.sh pull
./scripts/brain-sync.sh status
```

**Fedora**

```bash
cd /home/travis/Github/my_ai_brain
./scripts/brain-sync.sh pull
./scripts/brain-sync.sh status
```

- [ ] `status` shows `only-vault=0` (vault IDs are in local DB). Then use Cursor as usual.
- [ ] MCP already green? Keep the same Cursor window. **Reload Window** only if `open-brain` / `obsidian` / dashboard MCP is red.
- [ ] New chat still runs dashboard pickup (`dashboard_get_pending`) — that is independent of `brain-sync`.

---

## Same-day loop (Mac morning → Fedora afternoon → Mac)

| Step | Where | Action |
|------|--------|--------|
| 1 | Mac, leaving | `brain-sync push` · Obsidian stays open |
| 2 | Walk | LiveSync copies `thoughts.json` (both Obsidians still running) |
| 3 | Fedora, arriving | Wait for file · `brain-sync pull` · `status` |
| 4 | Fedora, work | Cursor / dashboard already up |
| 5 | Fedora, leaving | `brain-sync push` |
| 6 | Mac, arriving | Wait for file · `brain-sync pull` · `status` |

Do not sit down and search Open Brain **before** pull on that host. Notes in Obsidian can already look “in sync”; thoughts will not.

---

## Quick status cheat sheet

```bash
./scripts/brain-sync.sh status
```

| You want | Meaning |
|----------|---------|
| `only-vault=0` | After **pull**: this host has imported vault UUIDs |
| `only-local` high after a session | You captured here and have not **pushed** yet |
| File 0 bytes | **Stop.** Do not pull. Push from the healthy host |

---

## Optional — only if something is actually down

Stacks stay up. Use these **only** after reboot, crash, or MCP/health failure.

| | Mac | Fedora |
|--|-----|--------|
| Stack | `~/start-ai-brain.sh` then `--check-only` | `~/start-ai-brain.sh` then `--check-only` |
| Health | `~/Github/agentic-os-dashboard/scripts/health-check-travis.sh --quick` | `…/health-check-travis-fedora.sh` (full; `--quick` skips runner/auth) |
| Runner | LaunchAgent `com.agentic-os.agent-runner` | `systemctl --user status agentic-os-agent-runner` |
| Dashboard recreate | `./run-container-travis.sh` | `./run-container-travis-fedora.sh` |
| After sleep | Reload Cursor Window (sleepwatcher on Mac) | Reload Cursor Window |

Do **not** run Apple wrappers on Fedora (`run-container-travis.sh`, `health-check-travis.sh`).

---

## Never

- [ ] Quit Obsidian on the machine you just pushed from until LiveSync has sent `thoughts.json`
- [ ] `brain-sync pull` on a missing or **0-byte** `thoughts.json`
- [ ] `backup.sh` / `restore.sh` as the two-machine sync
- [ ] Copy `mcp.json`, `runs.db`, `jira.env`, `google-calendar.env`, or Supabase keys between hosts
- [ ] Point one host’s Open Brain at the other’s `:54321` / `:11434`

Jira / Calendar credentials are per-host (Fedora: `setup-jira-calendar-travis-fedora.sh`). Not a daily switch step.
