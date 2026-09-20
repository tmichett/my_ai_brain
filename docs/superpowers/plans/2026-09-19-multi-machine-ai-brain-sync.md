# Multi-machine AI Brain Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Amended 2026-09-20:** Freeze Travis-Mac_Apple live entrypoints. Intel/Fedora get their own scripts. Shared merge only. Do **not** implement until Travis asks.

**Goal:** Offline-first Open Brain on Travis-Mac_Apple, Travis-Mac-Intel, and Travis-Fedora, with UUID union-merge through the LiveSync vault so thoughts are not dropped when switching machines.

**Architecture:** Each host runs local Ollama + local Supabase. Shared `thoughts_merge.py` + `brain-sync.sh` do UUID union-merge. Travis-Mac_Apple daily scripts stay frozen. Travis-Mac-Intel and Travis-Fedora get separate start/ensure/health/dashboard wrappers that call the shared sync CLI. Dashboard `runs.db` and Supabase keys stay per-host.

**Tech Stack:** bash 3.2-safe scripts, Python 3 stdlib only for merge/sync helpers, Podman, local Supabase pgvector, Ollama `nomic-embed-text`, Cursor hooks, LaunchAgents (macOS) / systemd --user (Fedora).

**Spec:** `docs/superpowers/specs/2026-09-19-multi-machine-ai-brain-sync-design.md` (this repo). Dashboard pointer: `agentic-os-dashboard/docs/superpowers/specs/2026-09-19-multi-machine-ai-brain-sync-design.md`.

## Global Constraints

- Host display names: **Travis-Mac_Apple**, **Travis-Mac-Intel**, **Travis-Fedora** (never “other Mac” / generic linux).
- `AI_BRAIN_HOST` / `MACHINE_LABEL`: `travis-mac-apple` | `travis-mac-intel` | `travis-fedora`.
- Sync algorithm: UUID union-merge; preserve `id`; never dedupe by `content`.
- Freeze Travis-Mac_Apple: do **not** modify `ensure-ai-brain-services.sh`, `start-ai-brain.sh`, `run-container-travis.sh`, `health-check-travis.sh`, `backup.sh`, `restore.sh`, `verify.sh`, `cursor-hook-ensure-services.sh`, `cursor-hook-backup.sh`.
- Do **not** turn Apple scripts into aliases of a generic portable script.
- Intel and Fedora get **separate** named scripts (`*-travis-mac-intel`, `*-travis-fedora`), not `if linux` inside Apple files.
- UUID merge lives in **one** library (`thoughts_merge.py` + `brain-sync.sh`); do not fork per host.
- Apple joins the sync file via **manual** `brain-sync` in v1 (optional new hook file later; never edit Apple sessionStart ensure).
- Empty/invalid vault JSON on pull: no-op (do not truncate local DB).
- Push: union vault+local, atomic write; empty vault treated as empty list.
- `VAULT_DIR` == `OBSIDIAN_VAULT_DIR` == `KB_DIR` (rule has trailing slash) on that host.
- Do not sync `runs.db`, dashboard secret, or `SUPABASE_SERVICE_ROLE_KEY`.
- Embeddings regenerated locally with `nomic-embed-text` (768d).
- Envelope path: `${VAULT_DIR}/open-brain-sync/thoughts.json`, `version: 2`.
- Python merge library: stdlib only (no pip). Tests via `uv run pytest` if the repo has pytest; otherwise `python3 -m pytest` after `uv add --dev pytest` in my_ai_brain, or `python3 -m unittest`.
- No `git commit` / `git push` unless Travis explicitly asks that turn.
- Keep `run-container-travis.sh` and `health-check-travis.sh` as today’s Apple files (not aliases).
- Do not stub `docs/TRAVIS-MACOS-SETUP.md`.

## File map

**Create (`my_ai_brain`):**

- `scripts/lib/thoughts_merge.py`, `scripts/lib/load-ai-brain-env.sh`, `scripts/brain-sync.sh`
- `scripts/install-ai-brain.sh`
- `scripts/ensure-ai-brain-services-travis-mac-intel.sh`, `start-ai-brain-travis-mac-intel.sh`, `verify-travis-mac-intel.sh`, `cursor-hook-ensure-services-travis-mac-intel.sh`
- `scripts/ensure-ai-brain-services-travis-fedora.sh`, `start-ai-brain-travis-fedora.sh`, `verify-travis-fedora.sh`, `cursor-hook-ensure-services-travis-fedora.sh`
- `scripts/cursor-hook-brain-sync.sh` (optional; not wired on Apple in v1)
- `tests/test_thoughts_merge.py`
- `docs/MULTI-MACHINE.md`, `docs/TROUBLESHOOTING.md`, `docs/hosts/TRAVIS-MAC-APPLE.md`, `docs/hosts/TRAVIS-MAC-INTEL.md`, `docs/hosts/TRAVIS-FEDORA.md`

**Do not modify (`my_ai_brain` v1):** `scripts/backup.sh`, `restore.sh`, `verify.sh`, `ensure-ai-brain-services.sh`, `start-ai-brain.sh`, `cursor-hook-backup.sh`, `cursor-hook-ensure-services.sh`

**Modify (`my_ai_brain`):** `README.md` Multi-Machine section only (describe freeze-Apple + shared `brain-sync`)

**Create (`agentic-os-dashboard`):** `run-container-travis-mac-intel.sh`, `run-container-travis-fedora.sh`, `scripts/health-check-travis-mac-intel.sh`, `scripts/health-check-travis-fedora.sh`, `docs/TRAVIS-MAC-APPLE.md` (pointer), `docs/TRAVIS-MAC-INTEL.md`, `docs/TRAVIS-FEDORA.md`

**Do not modify (`agentic-os-dashboard` v1):** `run-container-travis.sh`, `scripts/health-check-travis.sh`, `docs/TRAVIS-MACOS-SETUP.md` body (may add a one-line “also see TRAVIS-MAC-APPLE.md” at the top only if needed)

**Modify (`agentic-os-dashboard`):** `docs/PORTABLE-SETUP.md` index, `backup-scripts/*` additive `OPENBRAIN_MODE=local`

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

### Task 4: Apple regression gate (no live-script edits)

**Files:** none (read-only)

**Interfaces:**

- Consumes: existing Apple stack
- Produces: proof M3 still works after Tasks 1–3 land as *new* files only

- [ ] **Step 1: Confirm Apple live files are unmodified**

```bash
cd /Users/travis/Github/my_ai_brain
git diff -- scripts/ensure-ai-brain-services.sh scripts/start-ai-brain.sh \
  scripts/backup.sh scripts/restore.sh scripts/verify.sh \
  scripts/cursor-hook-ensure-services.sh scripts/cursor-hook-backup.sh
cd /Users/travis/Github/agentic-os-dashboard
git diff -- run-container-travis.sh scripts/health-check-travis.sh
```

Expected: empty diffs for those paths.

- [ ] **Step 2: Run existing Apple health**

```bash
~/start-ai-brain.sh --check-only
/Users/travis/Github/agentic-os-dashboard/scripts/health-check-travis.sh --quick
```

Expected: same pass/fail character as before this project (not a new portable `health-check.sh`).

- [ ] **Step 3: Optional `brain-sync status` only** (after Task 3). Do not `push` until Travis confirms. Do not edit `hooks.json`.

---

### Task 4b: SKIPPED (do not wrap Apple backup/restore/hooks)

Do **not** replace `backup.sh`, `restore.sh`, `cursor-hook-backup.sh`, or `cursor-hook-ensure-services.sh`. Those stay dump-replace / Apple ensure. Sync is `brain-sync.sh` only.

---

### Task 5: Travis-Mac-Intel + Travis-Fedora ensure/start/verify

**Files:**

- Create: `scripts/ensure-ai-brain-services-travis-mac-intel.sh`
- Create: `scripts/start-ai-brain-travis-mac-intel.sh`
- Create: `scripts/verify-travis-mac-intel.sh`
- Create: `scripts/cursor-hook-ensure-services-travis-mac-intel.sh`
- Create: `scripts/ensure-ai-brain-services-travis-fedora.sh`
- Create: `scripts/start-ai-brain-travis-fedora.sh`
- Create: `scripts/verify-travis-fedora.sh`
- Create: `scripts/cursor-hook-ensure-services-travis-fedora.sh`

**Interfaces:**

- Consumes: `load-ai-brain-env.sh`, `brain-sync.sh`, host dashboard wrapper
- Produces: host start path that never execs Apple `ensure-ai-brain-services.sh`

- [ ] **Step 1: Intel ensure script** — copy *structure* of Apple `ensure-ai-brain-services.sh` into a **new** file. Differences required:
  - PATH prepend `/usr/local/bin` then `/opt/homebrew/bin`
  - `podman machine start` (Darwin)
  - Discover `supabase_db*` / `supabase_kong*` (do not hardcode `_travis`)
  - Dashboard recreate via `$AGENTIC_OS_REPO/run-container-travis-mac-intel.sh` only
  - `LOG_DIR="${HOME}/Library/Logs"`
  - After healthy start (non-hook): `"$SCRIPT_DIR/brain-sync.sh" pull` (stderr only)
  - Hook mode: JSON on stdout unchanged pattern; `brain-sync --hook pull` logs to `LOG_DIR`, not stdout

- [ ] **Step 2: Intel start + verify + hook wrappers**

`start-ai-brain-travis-mac-intel.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/ensure-ai-brain-services-travis-mac-intel.sh" "$@"
```

`cursor-hook-ensure-services-travis-mac-intel.sh` execs the Intel ensure with `--hook` only (do not call Apple ensure).

`verify-travis-mac-intel.sh`: copy Apple `verify.sh` checks but `MY_AI_BRAIN_REPO` from env, `node_modules` under that repo, DB discovery, plus `PYTHONPATH=.../scripts/lib` import of `thoughts_merge`.

- [ ] **Step 3: Fedora ensure script** — **new file**, not Intel with `if linux`:
  - No `podman machine`
  - No `launchctl`; optional `systemctl --user start agentic-os-dashboard.service`
  - `LOG_DIR="${HOME}/.local/state/ai-brain"`
  - Dashboard wrapper `run-container-travis-fedora.sh`
  - Then `brain-sync pull` as Intel
  - Matching `start-ai-brain-travis-fedora.sh`, `verify-travis-fedora.sh`, `cursor-hook-ensure-services-travis-fedora.sh`

- [ ] **Step 4: Do not run Intel/Fedora ensure on the M3** except syntax check:

```bash
bash -n /Users/travis/Github/my_ai_brain/scripts/ensure-ai-brain-services-travis-mac-intel.sh
bash -n /Users/travis/Github/my_ai_brain/scripts/ensure-ai-brain-services-travis-fedora.sh
```

Expected: no output, exit 0.

---

### Task 6: `install-ai-brain.sh` (Intel/Fedora only)

**Files:**

- Create: `scripts/install-ai-brain.sh`

- [ ] **Step 1: Implement installer**

Flags: `--host=travis-mac-intel|travis-fedora`, `--vault=`, `--yes`, `--force`

Behavior:

1. If `--host=travis-mac-apple`: write `~/.config/ai-brain/env` only with `--force`; **refuse** to change `~/start-ai-brain.sh` or `hooks.json`; print “Apple stack is frozen; use brain-sync.sh manually.”
2. For intel/fedora: `--vault` required; `test -d` and (`hot.md` or `AI Brain/hot.md`).
3. Write `~/.config/ai-brain/env`; `chmod 600`.
4. `mkdir -p "$VAULT_DIR/open-brain-sync"`
5. `ln -sf` host start script to `$HOME/start-ai-brain.sh` (`start-ai-brain-travis-mac-intel.sh` or `start-ai-brain-travis-fedora.sh`) — **never** Apple `start-ai-brain.sh` on those hosts.
6. `npm install` in `mcp-server`.
7. Print `setup-cursor-bridge.sh --vault … --memory-backend open-brain --brain-read-gate` and the host dashboard wrapper name.

Do not write `mcp.json` keys.

- [ ] **Step 2: Refuse to run full Intel install on Apple by default**

If `uname -m` is `arm64` and `--host=travis-mac-intel`, warn and require `--yes`. Do not overwrite Apple `~/start-ai-brain.sh` unless `--host` is intel/fedora **and** Travis is on that machine.

---

### Task 7: my_ai_brain documentation (Travis-named hosts)

**Files:**

- Create: `docs/MULTI-MACHINE.md`, `docs/TROUBLESHOOTING.md`
- Create: `docs/hosts/TRAVIS-MAC-APPLE.md`, `docs/hosts/TRAVIS-MAC-INTEL.md`, `docs/hosts/TRAVIS-FEDORA.md`
- Modify: `README.md` Multi-Machine Sync section only
- Modify: `docs/HOW-IT-WORKS.md` backup diagram to union-merge (prose/docs only)

- [ ] **Step 1: `docs/MULTI-MACHINE.md`** — topology, host table, freeze-Apple rule, shared `brain-sync` only, envelope v2, what does not sync, LiveSync empty-file rule, pointers to host docs.

- [ ] **Step 2: `docs/hosts/TRAVIS-MAC-APPLE.md`** — frozen live commands (`~/start-ai-brain.sh`, `run-container-travis.sh`, `health-check-travis.sh`); manual `brain-sync`; sibling `agentic-os-dashboard/docs/TRAVIS-MACOS-SETUP.md` (still the operational runbook) and `docs/TRAVIS-MAC-APPLE.md` pointer. **Do not** say `run-container-travis.sh` is an alias.

- [ ] **Step 3: `docs/hosts/TRAVIS-MAC-INTEL.md`** — **Travis-Mac-Intel**; `/usr/local`; `podman machine`; git ≥ 2.42; named Intel scripts; `$VAULT_DIR`; sibling dashboard Intel doc.

- [ ] **Step 4: `docs/hosts/TRAVIS-FEDORA.md`** — title contains **Travis-Fedora**; native Podman; systemd; `LOG_DIR=~/.local/state/ai-brain`; named Fedora scripts; sibling dashboard Fedora doc.

- [ ] **Step 5: `docs/TROUBLESHOOTING.md`** — include: Apple vs Intel vs Fedora start commands; `brain-sync` drift; do not run Fedora ensure on Apple; `supabase_db_travis` is Apple-only.

- [ ] **Step 6: README** — union-merge + freeze-Apple; Apple `backup.sh` remains legacy dump.

---

### Task 8: Dashboard Intel/Fedora wrappers + Travis host docs

**Files (repo `/Users/travis/Github/agentic-os-dashboard`):**

- Create: `run-container-travis-mac-intel.sh`
- Create: `run-container-travis-fedora.sh`
- Create: `docs/TRAVIS-MAC-APPLE.md` (short pointer to `TRAVIS-MACOS-SETUP.md`)
- Create: `docs/TRAVIS-MAC-INTEL.md`
- Create: `docs/TRAVIS-FEDORA.md`
- Modify: `docs/PORTABLE-SETUP.md` intro table only

**Do not:** create `run-container-travis-mac-apple.sh`, alias `run-container-travis.sh`, or stub `TRAVIS-MACOS-SETUP.md`.

- [ ] **Step 1: Intel wrapper**

```bash
#!/usr/bin/env bash
# Travis-Mac-Intel — set OBSIDIAN_VAULT_DIR to this machine's LiveSync vault.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="${HOME}/.local/bin:/usr/local/bin:/opt/homebrew/bin:${PATH:-}"
export MEMORY_BACKEND="${MEMORY_BACKEND:-open-brain}"
export OBSIDIAN_VAULT_DIR="${OBSIDIAN_VAULT_DIR:-}"
if [[ -z "$OBSIDIAN_VAULT_DIR" ]]; then
  echo "Set OBSIDIAN_VAULT_DIR in this script or the environment (Travis-Mac-Intel vault path)." >&2
  exit 1
fi
exec "$SCRIPT_DIR/run-container.sh" "$@"
```

- [ ] **Step 2: Fedora wrapper `run-container-travis-fedora.sh`** — comments say **Travis-Fedora**; SELinux note; empty vault default until install; `AGENTIC_OS_LOOP_WATCHER=1`; **no** `launchctl`.

- [ ] **Step 3: Docs**

`docs/TRAVIS-MAC-APPLE.md`:

```markdown
# Travis-Mac_Apple

Display name: **Travis-Mac_Apple** (`travis-mac-apple`). Apple Silicon M3 daily driver.

Operational runbook (unchanged): [TRAVIS-MACOS-SETUP.md](./TRAVIS-MACOS-SETUP.md)

Open Brain sync: manual `my_ai_brain/scripts/brain-sync.sh` — see that repo’s `docs/hosts/TRAVIS-MAC-APPLE.md`.

- Intel: [TRAVIS-MAC-INTEL.md](./TRAVIS-MAC-INTEL.md)
- Fedora: [TRAVIS-FEDORA.md](./TRAVIS-FEDORA.md)
```

`docs/TRAVIS-MAC-INTEL.md` / `docs/TRAVIS-FEDORA.md`: full first-time checklists using **host-specific** script names (`install-ai-brain.sh --host=travis-mac-intel|travis-fedora`, matching wrappers and health-check). Titles must contain **Travis-Mac-Intel** / **Travis-Fedora**.

`PORTABLE-SETUP.md`: first table lists the three Travis docs; Apple line still points at `TRAVIS-MACOS-SETUP.md` as the live runbook.

---

### Task 9: Host-specific health-check copies (do not alias Apple)

**Files:**

- Create: `scripts/health-check-travis-mac-intel.sh`
- Create: `scripts/health-check-travis-fedora.sh`

**Do not:** create `scripts/health-check.sh`, modify `health-check-travis.sh`, or `skill_patch` the Apple health-check skill.

- [ ] **Step 1: Intel health-check** — copy `health-check-travis.sh` to the new filename. Change:
  - Banner text **Travis-Mac-Intel**
  - Wrapper check: `run-container-travis-mac-intel.sh` not `run-container-travis.sh`
  - PATH `/usr/local/bin` first
  - git ≥ 2.42 warning (Intel stale git)
  - Section **Open Brain sync**: run `brain-sync status`; fail if thoughts.json is 0 bytes
  - Memory API 503 still pass for `open-brain`

- [ ] **Step 2: Fedora health-check** — copy Intel or Apple and adapt:
  - Banner **Travis-Fedora**
  - No `launchctl` section; systemd `--user` instead
  - `KB_DIR` parse must allow `/home`
  - Wrapper `run-container-travis-fedora.sh`
  - `brain-sync status` section
  - Skip Apple-only git `/usr/local/bin/git` trailer note or keep as warn-if-present

- [ ] **Step 3: On Apple, still run the old command**

```bash
cd /Users/travis/Github/agentic-os-dashboard
./scripts/health-check-travis.sh --quick
```

Expected: unchanged script. Do not run the Intel/Fedora copies as the Apple daily check.

---

### Task 10: Snapshot backups `OPENBRAIN_MODE=local`

**Files:**

- Modify: `backup-scripts/brain-snapshot-backup.sh` (additive mode only)
- Modify: `backup-scripts/brain-snapshot-backup.env.example`
- Modify: `backup-scripts/README.md`

Keep `OPENBRAIN_MODE` default **`ssh`** (hal9k). Do not change Apple cron unless Travis asks.

- [ ] **Step 1:** When `OPENBRAIN_MODE=local`: `podman exec "$DB_CONTAINER" pg_dump` on this host; thoughts JSON with IDs; comments for Travis-Mac_Apple / Intel / Fedora.

- [ ] **Step 2:** Restore drill uses `brain-sync pull` with `OPEN_BRAIN_SYNC_JSON=` override.

- [ ] **Step 3:** Example env snippets named **Travis-Mac_Apple**, **Travis-Mac-Intel**, **Travis-Fedora**.

---

### Task 11: Optional Apple sync hook (new file only, not wired)

**Files:**

- Create: `scripts/cursor-hook-brain-sync.sh`

- [ ] **Step 1:** New hook script: `--hook pull` on sessionStart-compatible JSON-empty success; push on sessionEnd. Logs to Apple `~/Library/Logs` or `LOG_DIR`.

- [ ] **Step 2:** Document in Apple host doc: **not** added to `~/.cursor/hooks.json` until Travis asks. Installing Intel/Fedora must not edit the M3 `hooks.json`.

- [ ] **Step 3:** Do **not** modify `ensure-ai-brain-services.sh` or Apple `start-ai-brain.sh`.

---

### Task 12: Spec self-check after implementation (future session)

- [ ] `git diff` on the frozen Apple file list is empty (except README/docs/HOW-IT-WORKS if those were allowed).
- [ ] Intel/Fedora scripts exist and `bash -n` clean; they do not `source`/`exec` Apple `ensure-ai-brain-services.sh`.
- [ ] Merge tests pass.
- [ ] Three host docs in both repos; `TRAVIS-MACOS-SETUP.md` still a full runbook, not a stub.
- [ ] Do not commit or push unless Travis asks.

---

## Execution notes for a future session

Do **not** use git worktrees. Edit the real clones:

- `/Users/travis/Github/my_ai_brain`
- `/Users/travis/Github/agentic-os-dashboard`

Suggested order: Tasks 1–3 (shared merge + `brain-sync`) → Task 4 Apple regression gate → Task 3 first **push** only with Travis watching → Tasks 5–9 Intel/Fedora scripts and docs → Task 10 snapshots → Task 11 leftover hook file.

**Two execution options when Travis says to implement:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks
2. **Inline Execution** — executing-plans in one session with checkpoints

