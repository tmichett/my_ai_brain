# Multi-machine AI Brain Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **This session (2026-09-19):** Spec + plan only. Do **not** implement tasks below until Travis asks.

**Goal:** Offline-first Open Brain on Travis-Mac_Apple, Travis-Mac-Intel, and Travis-Fedora, with UUID union-merge through the LiveSync vault so thoughts are not dropped when switching machines.

**Architecture:** Each host runs local Ollama + local Supabase. `scripts/lib/thoughts_merge.py` unions thought rows by UUID. `brain-sync.sh` pulls (insert missing IDs + re-embed) and pushes (atomic write of merged envelope to `open-brain-sync/thoughts.json`). Machine paths live in `~/.config/ai-brain/env`. Dashboard `runs.db` and Supabase keys stay per-host.

**Tech Stack:** bash 3.2-safe scripts, Python 3 stdlib only for merge/sync helpers, Podman, local Supabase pgvector, Ollama `nomic-embed-text`, Cursor hooks, LaunchAgents (macOS) / systemd --user (Fedora).

**Spec:** `docs/superpowers/specs/2026-09-19-multi-machine-ai-brain-sync-design.md` (this repo). Dashboard pointer: `agentic-os-dashboard/docs/superpowers/specs/2026-09-19-multi-machine-ai-brain-sync-design.md`.

## Global Constraints

- Host display names: **Travis-Mac_Apple**, **Travis-Mac-Intel**, **Travis-Fedora** (never “other Mac” / generic linux).
- `AI_BRAIN_HOST` / `MACHINE_LABEL`: `travis-mac-apple` | `travis-mac-intel` | `travis-fedora`.
- Sync algorithm: UUID union-merge; preserve `id`; never dedupe by `content`.
- Empty/invalid vault JSON on pull: no-op (do not truncate local DB).
- Push: union vault+local, atomic write; empty vault treated as empty list.
- No hardcoded `MBP-M3-RH`, `supabase_db_travis`, or `~/Library/Logs` in rewritten scripts.
- `VAULT_DIR` == `OBSIDIAN_VAULT_DIR` == `KB_DIR` (rule has trailing slash) on that host.
- Do not sync `runs.db`, dashboard secret, or `SUPABASE_SERVICE_ROLE_KEY`.
- Embeddings regenerated locally with `nomic-embed-text` (768d).
- Envelope path: `${VAULT_DIR}/open-brain-sync/thoughts.json`, `version: 2`.
- Python merge library: stdlib only (no pip). Tests via `uv run pytest` if the repo has pytest; otherwise `python3 -m pytest` after `uv add --dev pytest` in my_ai_brain, or `python3 -m unittest`.
- No `git commit` / `git push` unless Travis explicitly asks that turn.
- Keep `run-container-travis.sh` as an alias to Travis-Mac_Apple.

## File map

**Create (`my_ai_brain`):**

- `scripts/lib/thoughts_merge.py` — merge + validate envelope
- `scripts/lib/load-ai-brain-env.sh` — source `~/.config/ai-brain/env` + discover DB container
- `scripts/brain-sync.sh` — pull / push / status
- `scripts/install-ai-brain.sh` — host bootstrap
- `tests/test_thoughts_merge.py` — unit tests
- `docs/MULTI-MACHINE.md`, `docs/TROUBLESHOOTING.md`
- `docs/hosts/TRAVIS-MAC-APPLE.md`, `docs/hosts/TRAVIS-MAC-INTEL.md`, `docs/hosts/TRAVIS-FEDORA.md`

**Modify (`my_ai_brain`):** `scripts/backup.sh`, `restore.sh`, `verify.sh`, `ensure-ai-brain-services.sh`, `cursor-hook-backup.sh`, `cursor-hook-ensure-services.sh`, `README.md`

**Create (`agentic-os-dashboard`):** `run-container-travis-mac-apple.sh`, `run-container-travis-mac-intel.sh`, `run-container-travis-fedora.sh`, `scripts/health-check.sh`, `docs/TRAVIS-MAC-APPLE.md`, `docs/TRAVIS-MAC-INTEL.md`, `docs/TRAVIS-FEDORA.md`

**Modify (`agentic-os-dashboard`):** `run-container-travis.sh` (alias), `scripts/health-check-travis.sh` (alias), `docs/PORTABLE-SETUP.md`, `docs/TRAVIS-MACOS-SETUP.md` (stub), `backup-scripts/brain-snapshot-backup.sh`, `backup-scripts/brain-snapshot-backup.env.example`, `backup-scripts/README.md`

---

### Task 1: UUID union-merge library + tests

**Files:**

- Create: `tests/test_thoughts_merge.py`
- Create: `scripts/lib/thoughts_merge.py`

**Interfaces:**

- Consumes: nothing (pure)
- Produces: `validate_envelope(obj) -> list[dict]`, `merge_thoughts(vault: list, local: list) -> list`, `build_envelope(thoughts, machine: str, exported_at: str | None) -> dict`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_thoughts_merge.py`:

```python
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts" / "lib"))
from thoughts_merge import build_envelope, merge_thoughts, validate_envelope


def _t(i, content, updated, created="2026-01-01T00:00:00Z"):
    return {
        "id": i,
        "content": content,
        "metadata": {"type": "observation"},
        "created_at": created,
        "updated_at": updated,
    }


def test_only_local_kept():
    out = merge_thoughts([], [_t("a", "local", "2026-09-19T10:00:00Z")])
    assert [x["id"] for x in out] == ["a"]


def test_only_vault_kept():
    out = merge_thoughts([_t("b", "vault", "2026-09-19T10:00:00Z")], [])
    assert [x["id"] for x in out] == ["b"]


def test_newer_local_wins():
    vault = [_t("a", "old", "2026-09-19T10:00:00Z")]
    local = [_t("a", "new", "2026-09-19T12:00:00Z")]
    out = merge_thoughts(vault, local)
    assert out[0]["content"] == "new"


def test_newer_vault_wins():
    vault = [_t("a", "vault-new", "2026-09-19T12:00:00Z")]
    local = [_t("a", "local-old", "2026-09-19T10:00:00Z")]
    out = merge_thoughts(vault, local)
    assert out[0]["content"] == "vault-new"


def test_equal_timestamp_local_wins():
    ts = "2026-09-19T10:00:00Z"
    out = merge_thoughts([_t("a", "vault", ts)], [_t("a", "local", ts)])
    assert out[0]["content"] == "local"


def test_union_two_machines():
    vault = [_t("apple", "morning", "2026-09-19T10:00:00Z")]
    local = [_t("fedora", "afternoon", "2026-09-19T16:00:00Z")]
    ids = {x["id"] for x in merge_thoughts(vault, local)}
    assert ids == {"apple", "fedora"}


def test_validate_rejects_empty_bytes_as_error_type():
    try:
        validate_envelope("")
        assert False, "expected ValueError"
    except ValueError as e:
        assert "empty" in str(e).lower() or "invalid" in str(e).lower()


def test_validate_version2_roundtrip():
    thoughts = [_t("a", "x", "2026-09-19T10:00:00Z")]
    env = build_envelope(thoughts, "travis-mac-apple", "2026-09-19T10:00:00Z")
    assert env["version"] == 2
    assert env["thought_count"] == 1
    assert env["machine"] == "travis-mac-apple"
    parsed = validate_envelope(env)
    assert parsed[0]["id"] == "a"


def test_validate_rejects_count_mismatch():
    env = build_envelope([_t("a", "x", "2026-09-19T10:00:00Z")], "travis-fedora")
    env["thought_count"] = 99
    try:
        validate_envelope(env)
        assert False
    except ValueError:
        pass


def test_does_not_dedupe_by_content():
    vault = [_t("id1", "same text", "2026-09-19T10:00:00Z")]
    local = [_t("id2", "same text", "2026-09-19T11:00:00Z")]
    out = merge_thoughts(vault, local)
    assert len(out) == 2
```

- [ ] **Step 2: Run tests to verify they fail**

Run from `/Users/travis/Github/my_ai_brain`:

```bash
python3 -m pytest tests/test_thoughts_merge.py -v
```

Expected: FAIL with `ModuleNotFoundError: No module named 'thoughts_merge'` or import error.

If pytest is missing:

```bash
uv add --dev pytest
uv run pytest tests/test_thoughts_merge.py -v
```

- [ ] **Step 3: Write minimal implementation**

Create `scripts/lib/thoughts_merge.py`:

```python
"""UUID union-merge for Open Brain thought envelopes (version 2)."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any


def _parse_ts(value: str | None) -> datetime:
    if not value:
        return datetime.min.replace(tzinfo=timezone.utc)
    text = value.replace("Z", "+00:00")
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return datetime.min.replace(tzinfo=timezone.utc)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def validate_envelope(obj: Any) -> list[dict]:
    if obj is None or obj == "":
        raise ValueError("empty envelope")
    if isinstance(obj, (bytes, bytearray)):
        if len(obj) == 0:
            raise ValueError("empty envelope")
        obj = obj.decode("utf-8")
    if isinstance(obj, str):
        if not obj.strip():
            raise ValueError("empty envelope")
        try:
            obj = json.loads(obj)
        except json.JSONDecodeError as exc:
            raise ValueError(f"invalid json: {exc}") from exc
    if not isinstance(obj, dict):
        raise ValueError("invalid envelope")
    version = obj.get("version")
    if version is None or int(version) < 2:
        raise ValueError("envelope version must be >= 2")
    thoughts = obj.get("thoughts")
    if thoughts is None:
        thoughts = []
    if not isinstance(thoughts, list):
        raise ValueError("thoughts must be a list")
    count = obj.get("thought_count")
    if count is not None and int(count) != len(thoughts):
        raise ValueError("thought_count mismatch")
    out: list[dict] = []
    for row in thoughts:
        if not isinstance(row, dict) or not row.get("id") or "content" not in row:
            raise ValueError("thought missing id or content")
        out.append(
            {
                "id": str(row["id"]),
                "content": row["content"],
                "metadata": row.get("metadata") or {},
                "created_at": row.get("created_at"),
                "updated_at": row.get("updated_at"),
            }
        )
    return out


def merge_thoughts(vault: list[dict], local: list[dict]) -> list[dict]:
    by_id: dict[str, dict] = {}
    for row in vault:
        by_id[str(row["id"])] = row
    for row in local:
        rid = str(row["id"])
        if rid not in by_id:
            by_id[rid] = row
            continue
        if _parse_ts(row.get("updated_at")) >= _parse_ts(by_id[rid].get("updated_at")):
            by_id[rid] = row
    return sorted(by_id.values(), key=lambda r: (r.get("created_at") or "", r["id"]))


def build_envelope(
    thoughts: list[dict],
    machine: str,
    exported_at: str | None = None,
) -> dict:
    stamp = exported_at or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return {
        "version": 2,
        "exported_at": stamp,
        "machine": machine,
        "thought_count": len(thoughts),
        "thoughts": thoughts,
    }


def load_envelope_file(path: str) -> list[dict]:
    """Return thoughts, or raise ValueError for empty/invalid. Missing file is empty list."""
    from pathlib import Path

    p = Path(path)
    if not p.exists():
        return []
    raw = p.read_bytes()
    if len(raw) == 0:
        raise ValueError("empty envelope")
    return validate_envelope(raw.decode("utf-8"))
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/travis/Github/my_ai_brain
uv run pytest tests/test_thoughts_merge.py -v
```

Expected: all tests PASS.

- [ ] **Step 5: Stop for Travis commit (do not commit unless asked)**

Working tree should contain only the test + library. Do not `git add` unless Travis asks.

---

### Task 2: Env loader + DB discovery

**Files:**

- Create: `scripts/lib/load-ai-brain-env.sh`
- Test: shellcheck + sourced smoke

**Interfaces:**

- Consumes: `~/.config/ai-brain/env`, `~/.cursor/agentic-os.env`
- Produces: exported `AI_BRAIN_HOST`, `VAULT_DIR`, `MY_AI_BRAIN_REPO`, `AGENTIC_OS_REPO`, `DB_CONTAINER`, `LOG_DIR`, `OPEN_BRAIN_SYNC_JSON`, `OLLAMA_URL`, `SUPABASE_URL`, `OLLAMA_EMBED_MODEL`

- [ ] **Step 1: Write `scripts/lib/load-ai-brain-env.sh`**

```bash
#!/usr/bin/env bash
# Source from other scripts:  # shellcheck source=scripts/lib/load-ai-brain-env.sh
# shellcheck disable=SC1090
set -euo pipefail

_ai_brain_config="${AI_BRAIN_ENV_FILE:-${HOME}/.config/ai-brain/env}"
_agentic_env="${HOME}/.cursor/agentic-os.env"

if [[ -f "$_agentic_env" ]]; then
  # shellcheck disable=SC1090
  source "$_agentic_env"
fi
if [[ -f "$_ai_brain_config" ]]; then
  # shellcheck disable=SC1090
  source "$_ai_brain_config"
fi

AI_BRAIN_HOST="${AI_BRAIN_HOST:-${MACHINE_LABEL:-}}"
VAULT_DIR="${VAULT_DIR:-${OBSIDIAN_VAULT_DIR:-}}"
MY_AI_BRAIN_REPO="${MY_AI_BRAIN_REPO:-${HOME}/Github/my_ai_brain}"
AGENTIC_OS_REPO="${AGENTIC_OS_REPO:-${HOME}/Github/agentic-os-dashboard}"
OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
SUPABASE_URL="${SUPABASE_URL:-http://127.0.0.1:54321}"
OLLAMA_EMBED_MODEL="${OLLAMA_EMBED_MODEL:-nomic-embed-text}"

if [[ -z "${LOG_DIR:-}" ]]; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    LOG_DIR="${HOME}/Library/Logs"
  else
    LOG_DIR="${HOME}/.local/state/ai-brain"
  fi
fi
mkdir -p "$LOG_DIR"

if [[ -z "${DB_CONTAINER:-}" ]]; then
  DB_CONTAINER="$(podman ps --filter "name=supabase_db" --format '{{.Names}}' 2>/dev/null | head -1 || true)"
fi

if [[ -n "${VAULT_DIR:-}" ]]; then
  OPEN_BRAIN_SYNC_JSON="${OPEN_BRAIN_SYNC_JSON:-${VAULT_DIR}/open-brain-sync/thoughts.json}"
fi

export AI_BRAIN_HOST VAULT_DIR MY_AI_BRAIN_REPO AGENTIC_OS_REPO
export DB_CONTAINER LOG_DIR OPEN_BRAIN_SYNC_JSON
export OLLAMA_URL SUPABASE_URL OLLAMA_EMBED_MODEL
```

- [ ] **Step 2: Smoke-source without a config file**

```bash
bash -c 'set -euo pipefail; source /Users/travis/Github/my_ai_brain/scripts/lib/load-ai-brain-env.sh; echo LOG_DIR=$LOG_DIR; echo DB=$DB_CONTAINER'
```

Expected on Travis-Mac_Apple: `LOG_DIR` ends with `Library/Logs`; `DB` is `supabase_db_travis` if containers are up (discovery, not hardcode).

---

### Task 3: `brain-sync.sh` CLI

**Files:**

- Create: `scripts/brain-sync.sh`

**Interfaces:**

- Consumes: `load-ai-brain-env.sh`, `thoughts_merge.py`, `podman exec $DB_CONTAINER psql`, Ollama embed API
- Produces: `pull` / `push` / `status` exit codes: 0 ok, 1 service error, 2 invalid envelope on interactive pull

- [ ] **Step 1: Implement `scripts/brain-sync.sh`**

The script must:

1. `source` the env loader from `SCRIPT_DIR/lib/load-ai-brain-env.sh`.
2. Require `VAULT_DIR`, `DB_CONTAINER`, `AI_BRAIN_HOST`.
3. `dump_local()` via `psql` `json_agg` of `id, content, metadata, created_at, updated_at` (no embeddings).
4. `status`: print local count, vault count (0 if missing/empty without failing), only-local / only-vault ID counts using `thoughts_merge.merge_thoughts` in a python helper invoked as:

```bash
python3 - "$OPEN_BRAIN_SYNC_JSON" <<'PY'
# argv path + stdin local json array
...
PY
```

5. `push`:
   - `load_envelope_file`: missing → `[]`; empty/invalid → warn and `[]`
   - merge with local dump
   - `mkdir -p "$(dirname "$OPEN_BRAIN_SYNC_JSON")"`
   - write `$OPEN_BRAIN_SYNC_JSON.tmp` then `mv`
6. `pull`:
   - empty/invalid file: print WARN, exit 0 if `--hook`, else exit 2
   - for each ID in vault not in local: INSERT with explicit `id`, embed via Ollama `/api/embed` (same request shape as current `restore.sh`)
   - SQL must parameterize via Python `psycopg` **or** keep `podman exec psql` but pass UUID in the INSERT column list: `INSERT INTO public.thoughts (id, content, embedding, metadata, created_at, updated_at) ... ON CONFLICT (id) DO NOTHING`

Use `ON CONFLICT (id) DO NOTHING` so pull is idempotent and never overwrites.

Do **not** copy `restore.sh`’s `WHERE NOT EXISTS (content = …)`.

Include `--hook` for silent Cursor use.

- [ ] **Step 2: Manual status on Travis-Mac_Apple (no push yet)**

```bash
cd /Users/travis/Github/my_ai_brain
./scripts/brain-sync.sh status
```

Expected: local count > 0 if Open Brain is up; vault file may be missing (counts 0) until first push.

- [ ] **Step 3: Do not push a v2 file until Travis confirms** first push overwrites the LiveSync path. After confirmation:

```bash
./scripts/brain-sync.sh push
./scripts/brain-sync.sh status
```

Expected: `only-local=0`; vault `thought_count` equals local count.

---

### Task 4: Point backup/restore/hooks at union-merge

**Files:**

- Modify: `scripts/backup.sh`
- Modify: `scripts/restore.sh`
- Modify: `scripts/cursor-hook-backup.sh`
- Modify: `scripts/cursor-hook-ensure-services.sh`

**Interfaces:**

- Consumes: `brain-sync.sh`
- Produces: same CLI names so existing docs/hooks keep working

- [ ] **Step 1: Replace `backup.sh` body** with:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/brain-sync.sh" push "$@"
```

- [ ] **Step 2: Replace `restore.sh` body** with:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/brain-sync.sh" pull "$@"
```

- [ ] **Step 3: `cursor-hook-backup.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/brain-sync.sh" --hook push
```

- [ ] **Step 4: `cursor-hook-ensure-services.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${MY_AI_BRAIN_REPO:-$SCRIPT_DIR/..}"
"${REPO}/scripts/ensure-ai-brain-services.sh" --hook
"${REPO}/scripts/brain-sync.sh" --hook pull || true
```

Keep ensure-hook JSON-on-stdout behavior: pull must not print non-JSON on stdout in `--hook` mode (log to `LOG_DIR`).

---

### Task 5: Portable `ensure-ai-brain-services.sh` + `verify.sh`

**Files:**

- Modify: `scripts/ensure-ai-brain-services.sh`
- Modify: `scripts/verify.sh`

**Interfaces:**

- Consumes: `load-ai-brain-env.sh`
- Produces: start Ollama, all `supabase_*`, dashboard via `AGENTIC_OS_CONTAINER_SCRIPT` or `run-container-travis-${host}.sh`

- [ ] **Step 1: Replace hardcoded names**

In `ensure-ai-brain-services.sh`:

- `LOG_FILE="${LOG_DIR}/ensure-ai-brain-services.log"` after sourcing loader
- `services_healthy`: Kong = first `podman ps --filter name=supabase_kong` (not `supabase_kong_travis`)
- `resolve_dashboard_script`: prefer `$AGENTIC_OS_CONTAINER_SCRIPT`, then `$AGENTIC_OS_REPO/run-container-${AI_BRAIN_HOST}.sh` mapping:
  - `travis-mac-apple` → `run-container-travis-mac-apple.sh` then `run-container-travis.sh`
  - `travis-mac-intel` → `run-container-travis-mac-intel.sh`
  - `travis-fedora` → `run-container-travis-fedora.sh`
- Darwin-only: `podman machine start`; Linux skip
- Darwin-only: `launchctl kickstart`; Linux: `systemctl --user start agentic-os-dashboard.service` if unit exists, else warn

- [ ] **Step 2: `verify.sh`**

- Source loader
- MCP `node_modules` check: `"$MY_AI_BRAIN_REPO/mcp-server/node_modules"`
- DB container from `$DB_CONTAINER`
- Add check: `open-brain-sync` parent dir writable if `VAULT_DIR` set
- Add check: `python3 -c "import thoughts_merge"` via `PYTHONPATH=$MY_AI_BRAIN_REPO/scripts/lib`

- [ ] **Step 3: Run on Travis-Mac_Apple**

```bash
~/start-ai-brain.sh --check-only
/Users/travis/Github/my_ai_brain/scripts/verify.sh
```

Expected: all OK; no references to missing `_travis` names if containers use that name still (discovery should still find them).

---

### Task 6: `install-ai-brain.sh`

**Files:**

- Create: `scripts/install-ai-brain.sh`

- [ ] **Step 1: Implement installer**

Flags: `--host=travis-mac-apple|travis-mac-intel|travis-fedora`, `--vault=`, `--yes`

Behavior:

1. Validate `--host` against the three values.
2. `--vault` required; `test -d` and (`hot.md` or `AI Brain/hot.md`).
3. Write `~/.config/ai-brain/env` with `AI_BRAIN_HOST`, `VAULT_DIR`, `MY_AI_BRAIN_REPO` (repo of this script), `LOG_DIR` default by OS.
4. `chmod 600` the env file.
5. `mkdir -p "$VAULT_DIR/open-brain-sync"`
6. `ln -sf "$MY_AI_BRAIN_REPO/scripts/start-ai-brain.sh" "$HOME/start-ai-brain.sh"`
7. `(cd "$MY_AI_BRAIN_REPO/mcp-server" && npm install)`
8. Print next commands including dashboard bridge with the **same** `--vault`.

Do not write `mcp.json` keys here (per-instance Supabase secret).

- [ ] **Step 2: Dry-run on Apple (do not overwrite env without Travis)**

First implementation should skip writing if `~/.config/ai-brain/env` exists unless `--force`.

---

### Task 7: my_ai_brain documentation (Travis-named hosts)

**Files:**

- Create: `docs/MULTI-MACHINE.md`
- Create: `docs/TROUBLESHOOTING.md`
- Create: `docs/hosts/TRAVIS-MAC-APPLE.md`
- Create: `docs/hosts/TRAVIS-MAC-INTEL.md`
- Create: `docs/hosts/TRAVIS-FEDORA.md`
- Modify: `README.md` (Multi-Machine Sync section — replace dump/restore wording with UUID union-merge)

**Interfaces:** Prose only. Copy rules and topology from the spec. Every host file starts with the display name + `AI_BRAIN_HOST`.

- [ ] **Step 1: Write `docs/MULTI-MACHINE.md`** with these sections exactly:

1. Title: My AI Brain — Multi-machine sync (Travis)
2. Topology diagram (spec architecture)
3. Host table (three Travis names)
4. UUID union-merge (push/pull/status)
5. Envelope path and version 2 schema
6. What does not sync
7. Session hooks
8. LiveSync empty-file rule
9. Pointers to `docs/hosts/TRAVIS-*.md` and dashboard `docs/TRAVIS-*.md`

- [ ] **Step 2: Write `docs/hosts/TRAVIS-MAC-APPLE.md`**

Must include: this is the current M3 daily driver; vault `/Users/travis/Documents/MBP-M3-RH/Obsidian-Work-Vault/Obsidian-Work`; `~/start-ai-brain.sh`; LaunchAgents; sleepwatcher; `run-container-travis.sh` alias; health-check command; sibling dashboard doc `agentic-os-dashboard/docs/TRAVIS-MAC-APPLE.md`.

- [ ] **Step 3: Write `docs/hosts/TRAVIS-MAC-INTEL.md`**

Must include: **Travis-Mac-Intel**; Homebrew `/usr/local`; `podman machine`; git ≥ 2.42 / stale `/usr/local/bin/git`; headroom x86_64; vault path filled at install (`$VAULT_DIR`); no copied M3 paths as required values; sleepwatcher optional; LaunchAgents; sibling dashboard doc.

- [ ] **Step 4: Write `docs/hosts/TRAVIS-FEDORA.md`**

Must include the words **Travis-Fedora** in the title and first paragraph; native Podman; `dnf` packages; `LOG_DIR=~/.local/state/ai-brain`; systemd `--user`; SELinux `:z`; no sleepwatcher; Reload Cursor after suspend; sibling `agentic-os-dashboard/docs/TRAVIS-FEDORA.md`.

- [ ] **Step 5: Write `docs/TROUBLESHOOTING.md`** table rows at least:

| Symptom | Hosts | Fix |
|---------|-------|-----|
| MCP red after sleep | Apple, Intel | Reload Window; sleepwatcher on macOS |
| MCP red after reboot | all | `~/start-ai-brain.sh` |
| `only-vault > 0` | all | `brain-sync pull` |
| `only-local > 0` | all | `brain-sync push` |
| thoughts.json 0 bytes | all | do not pull; push from a host with rows; restore snapshot if all DBs wrong |
| `supabase_db_travis` not found | Intel, Fedora | discovery via `supabase_db`; do not copy Apple name |
| SELinux vault mount denied | Travis-Fedora | `:z` on volume; `chcon` if needed |
| `Library/Logs` missing | Travis-Fedora | `LOG_DIR` in env |
| git trailer error | Intel especially | git ≥ 2.42, remove stale `/usr/local/bin/git` |
| dashboard memory 503 | all with `open-brain` | expected |
| Ollama missing nomic-embed-text | all | `podman exec ollama ollama pull nomic-embed-text` |

- [ ] **Step 6: Update README Multi-Machine Sync** to describe union-merge, not replace-dump.

---

### Task 8: Dashboard wrappers + Travis host docs

**Files (repo `/Users/travis/Github/agentic-os-dashboard`):**

- Create: `run-container-travis-mac-apple.sh`
- Modify: `run-container-travis.sh` to exec mac-apple
- Create: `run-container-travis-mac-intel.sh`
- Create: `run-container-travis-fedora.sh`
- Create: `docs/TRAVIS-MAC-APPLE.md` (move content from `TRAVIS-MACOS-SETUP.md`, update names)
- Replace: `docs/TRAVIS-MACOS-SETUP.md` with a stub pointing at `TRAVIS-MAC-APPLE.md`
- Create: `docs/TRAVIS-MAC-INTEL.md`
- Create: `docs/TRAVIS-FEDORA.md`
- Modify: `docs/PORTABLE-SETUP.md` intro table of Travis hosts

- [ ] **Step 1: Apple wrapper**

`run-container-travis-mac-apple.sh` is a copy of current `run-container-travis.sh` (preserve behavior). Then `run-container-travis.sh` becomes:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/run-container-travis-mac-apple.sh" "$@"
```

- [ ] **Step 2: Intel wrapper** — copy `config/run-container-linux.example.sh` pattern but Darwin:

```bash
#!/usr/bin/env bash
# Travis-Mac-Intel — set OBSIDIAN_VAULT_DIR to this machine's LiveSync vault.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MEMORY_BACKEND="${MEMORY_BACKEND:-open-brain}"
export OBSIDIAN_VAULT_DIR="${OBSIDIAN_VAULT_DIR:-}"
if [[ -z "$OBSIDIAN_VAULT_DIR" ]]; then
  echo "Set OBSIDIAN_VAULT_DIR in this script or the environment (Travis-Mac-Intel vault path)." >&2
  exit 1
fi
exec "$SCRIPT_DIR/run-container.sh" "$@"
```

After Travis fills the path, hardcode the default like Apple’s wrapper.

- [ ] **Step 3: Fedora wrapper `run-container-travis-fedora.sh`**

Same as Intel but comments say **Travis-Fedora**, and document SELinux. Default `OBSIDIAN_VAULT_DIR` empty until install. `AGENTIC_OS_LOOP_WATCHER` default 1. Do not set Apple LaunchAgent assumptions.

- [ ] **Step 4: Docs**

`docs/TRAVIS-MAC-APPLE.md`: retitle every “Travis macOS” / MBP-M3-RH setup to **Travis-Mac_Apple**. Keep the existing operational checklists from `TRAVIS-MACOS-SETUP.md`. Add Open Brain sync: `brain-sync` pull on start, push on session end; link `my_ai_brain/docs/hosts/TRAVIS-MAC-APPLE.md`.

`docs/TRAVIS-MACOS-SETUP.md` stub:

```markdown
# Moved

This machine’s runbook is **[TRAVIS-MAC-APPLE.md](./TRAVIS-MAC-APPLE.md)** (Travis-Mac_Apple, Apple Silicon M3).

- Intel Mac: [TRAVIS-MAC-INTEL.md](./TRAVIS-MAC-INTEL.md)
- Fedora: [TRAVIS-FEDORA.md](./TRAVIS-FEDORA.md)
```

`docs/TRAVIS-MAC-INTEL.md` and `docs/TRAVIS-FEDORA.md`: full first-time checklists (podman, node, supabase CLI, clone both repos, `install-ai-brain.sh --host=…`, `setup-cursor-bridge.sh --vault … --memory-backend open-brain --brain-read-gate`, wrapper, verify, health-check). Title must contain **Travis-Mac-Intel** / **Travis-Fedora**.

`PORTABLE-SETUP.md`: first table lists the three Travis docs before generic portable notes.

---

### Task 9: Portable health-check + sync drift

**Files:**

- Create: `scripts/health-check.sh` in agentic-os-dashboard
- Modify: `scripts/health-check-travis.sh` to exec it
- Modify: `~/.cursor/skills/cursor-os/health-check/SKILL.md` Memory Layer section (via dashboard manage API / skill_patch — do **not** raw `cp` into `~/.cursor/skills`)

- [ ] **Step 1: Extract `health-check-travis.sh` into `health-check.sh`**

Keep all existing Apple checks. Parameterize:

- Wrapper script name from `AGENTIC_OS_CONTAINER_SCRIPT` / host
- LaunchAgent section: skip unless `uname` is Darwin
- systemd section: if Linux, `systemctl --user is-active agentic-os-dashboard.service` (warn if missing)
- `KB_DIR` parse: do not regex only `/Users`; allow `/home`
- New section **Open Brain sync**:
  - if `OPEN_BRAIN_SYNC_JSON` or `$VAULT_DIR/open-brain-sync/thoughts.json` exists
  - fail if size 0
  - run `"$MY_AI_BRAIN_REPO/scripts/brain-sync.sh" status` and warn on `only-vault`/`only-local` if the CLI prints those tokens
- Memory API: keep 503 as **pass** for `MEMORY_BACKEND=open-brain`

- [ ] **Step 2: Alias**

```bash
#!/usr/bin/env bash
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/health-check.sh" "$@"
```

in `health-check-travis.sh`.

- [ ] **Step 3: Run on Travis-Mac_Apple**

```bash
cd /Users/travis/Github/agentic-os-dashboard
./scripts/health-check.sh --quick
```

Expected: existing passes plus sync section (warn until first v2 push).

- [ ] **Step 4: Patch health-check skill Memory Layer** via dashboard `skill_patch` so SQLite UNREACHABLE/503 is not a failure when `MEMORY_BACKEND=open-brain`; probe Open Brain REST instead. Do not `cp` into `~/.cursor/skills`.

---

### Task 10: Snapshot backups `OPENBRAIN_MODE=local`

**Files:**

- Modify: `backup-scripts/brain-snapshot-backup.sh`
- Modify: `backup-scripts/brain-snapshot-backup.env.example`
- Modify: `backup-scripts/README.md`

- [ ] **Step 1: Add mode**

`OPENBRAIN_MODE="${OPENBRAIN_MODE:-ssh}"` for backward compatibility with hal9k.

When `OPENBRAIN_MODE=local`:

- `DB_CONTAINER` from env or podman discovery
- `pg_dump` via `podman exec "$DB_CONTAINER"` (no SSH)
- thoughts JSON via the same dump shape as `brain-sync` (ids preserved)
- Example env comments for **Travis-Mac_Apple**, **Travis-Mac-Intel**, **Travis-Fedora** (user-level launchd/cron or systemd timer; do not require root SSH)

- [ ] **Step 2: Document restore drill** in README using `OPEN_BRAIN_SYNC_JSON=/path/from/snapshot/thoughts.json brain-sync pull`

- [ ] **Step 3: Add example `brain-snapshot-backup.env` snippets** named in comments:

```
# Travis-Mac_Apple (local Supabase)
OPENBRAIN_MODE=local
VAULT_DIR=/Users/travis/Documents/MBP-M3-RH/Obsidian-Work-Vault/Obsidian-Work
BACKUP_USER=travis

# Travis-Mac-Intel — set VAULT_DIR to that host's LiveSync path
# Travis-Fedora — LOG/SNAPSHOT on Linux paths; OPENBRAIN_MODE=local
```

---

### Task 11: Wire start-ai-brain pull + README verify

**Files:**

- Modify: `scripts/ensure-ai-brain-services.sh` `main()` after successful start: if not `--hook` and not `--check-only`, run `brain-sync.sh pull` then `status` to stderr
- Modify: `docs/HOW-IT-WORKS.md` backup diagram to union-merge
- Modify: `docs/USAGE.md` if it mentions replace-dump restore

- [ ] **Step 1:** Non-hook `start-ai-brain.sh` path pulls after health.
- [ ] **Step 2:** Update HOW-IT-WORKS “Backup & Sync Flow” to UUID union, not replace.
- [ ] **Step 3:** Re-run `verify.sh` and `health-check.sh --quick` on Travis-Mac_Apple.

---

### Task 12: Spec self-check after implementation (future session)

- [ ] Grep rewritten scripts for `MBP-M3-RH`, `supabase_db_travis`, `Library/Logs` — allowed only in **Apple host docs** and env **examples**, not in generic script defaults.
- [ ] Confirm three dashboard docs and three my_ai_brain host docs exist with Travis names.
- [ ] Confirm merge tests still pass.
- [ ] Do not commit or push unless Travis asks.

---

## Execution notes for a future session

Do **not** use git worktrees. Edit the real clones:

- `/Users/travis/Github/my_ai_brain`
- `/Users/travis/Github/agentic-os-dashboard`

Suggested order: Tasks 1 → 5 on Apple first (no data loss on this machine), then Task 3 first push with Travis watching LiveSync, then docs (7–8), then health-check/snapshots (9–10).

**Two execution options when Travis says to implement:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks
2. **Inline Execution** — executing-plans in one session with checkpoints
