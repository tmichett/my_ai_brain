#!/usr/bin/env python3
"""Open Brain UUID union-merge CLI. Invoked by scripts/brain-sync.sh."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

from thoughts_merge import build_envelope, load_envelope_file, merge_thoughts, validate_envelope


def _hook() -> bool:
    return os.environ.get("BRAIN_SYNC_HOOK", "") == "1"


def log(msg: str) -> None:
    stream = sys.stderr if _hook() else sys.stdout
    print(msg, file=stream)


def die(msg: str, code: int = 1) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    raise SystemExit(code)


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def dump_local(db: str) -> list[dict]:
    sql = """
SELECT COALESCE(json_agg(
  json_build_object(
    'id', id,
    'content', content,
    'metadata', metadata,
    'created_at', created_at,
    'updated_at', updated_at
  ) ORDER BY created_at ASC
), '[]'::json)
FROM public.thoughts;
"""
    result = subprocess.run(
        ["podman", "exec", db, "psql", "-U", "postgres", "-t", "-A", "-c", sql],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        die(f"psql dump failed: {result.stderr.strip()[:200]}")
    raw = result.stdout.strip()
    if not raw:
        return []
    data = json.loads(raw)
    if not isinstance(data, list):
        return []
    return data


def local_ids(thoughts: list[dict]) -> set[str]:
    return {str(t["id"]) for t in thoughts if t.get("id")}


def vault_thoughts(path: str) -> list[dict] | None:
    """None means invalid/empty (pull must no-op). Missing file → []."""
    p = Path(path)
    if not p.exists():
        return []
    try:
        return load_envelope_file(path)
    except ValueError as exc:
        log(f"WARN: vault envelope unusable ({exc})")
        return None


def cmd_status() -> int:
    db = env("DB_CONTAINER")
    path = env("OPEN_BRAIN_SYNC_JSON")
    if not db:
        die("DB_CONTAINER is empty — is Supabase running?")
    local = dump_local(db)
    vault = vault_thoughts(path)
    if vault is None:
        log(f"local={len(local)} vault=INVALID/EMPTY path={path or '<unset>'}")
        return 0
    merged = merge_thoughts(vault, local)
    only_local = local_ids(local) - local_ids(vault)
    only_vault = local_ids(vault) - local_ids(local)
    age = ""
    if Path(path).exists() and Path(path).stat().st_size:
        try:
            env_obj = json.loads(Path(path).read_text())
            age = env_obj.get("exported_at", "")
            machine = env_obj.get("machine", "")
        except Exception:
            age = ""
            machine = ""
    else:
        machine = ""
    log(
        f"local={len(local)} vault={len(vault)} union={len(merged)} "
        f"only-local={len(only_local)} only-vault={len(only_vault)} "
        f"exported_at={age or '-'} machine={machine or '-'} file={path or '-'}"
    )
    if Path(path).exists() and Path(path).stat().st_size == 0:
        log("WARN: thoughts.json is zero bytes — do not pull; push from a host with rows")
    if only_vault:
        log("WARN: only-vault > 0 — run: brain-sync pull")
    if only_local:
        log("WARN: only-local > 0 — run: brain-sync push")
    return 0


def cmd_push() -> int:
    db = env("DB_CONTAINER")
    path = env("OPEN_BRAIN_SYNC_JSON")
    machine = env("AI_BRAIN_HOST") or os.uname().nodename
    if not db:
        die("DB_CONTAINER is empty — is Supabase running?")
    if not path:
        die("OPEN_BRAIN_SYNC_JSON / VAULT_DIR is unset")
    local = dump_local(db)
    vault: list[dict] = []
    p = Path(path)
    if p.exists():
        try:
            vault = load_envelope_file(path)
        except ValueError as exc:
            log(f"WARN: treating vault as empty ({exc})")
            vault = []
    merged = merge_thoughts(vault, local)
    envelope = build_envelope(merged, machine)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(envelope, indent=2, default=str) + "\n")
    tmp.replace(p)
    log(f"Pushed {envelope['thought_count']} thoughts → {path} (machine={machine})")
    return 0


def _embed(content: str, ollama_url: str, model: str) -> list[float]:
    req = urllib.request.Request(
        f"{ollama_url.rstrip('/')}/api/embed",
        data=json.dumps({"model": model, "input": content}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read())
    return data["embeddings"][0]


def _sql_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def cmd_pull() -> int:
    db = env("DB_CONTAINER")
    path = env("OPEN_BRAIN_SYNC_JSON")
    ollama = env("OLLAMA_URL", "http://127.0.0.1:11434")
    model = env("OLLAMA_EMBED_MODEL", "nomic-embed-text")
    if not db:
        die("DB_CONTAINER is empty — is Supabase running?")
    if not path:
        die("OPEN_BRAIN_SYNC_JSON / VAULT_DIR is unset")
    vault = vault_thoughts(path)
    if vault is None:
        log("WARN: pull skipped (empty or invalid vault JSON) — local DB unchanged")
        return 0 if _hook() else 2
    if not vault:
        log("Nothing to pull (vault file missing or empty list).")
        return 0
    local = dump_local(db)
    have = local_ids(local)
    inserted = 0
    skipped = 0
    for i, thought in enumerate(vault, 1):
        tid = str(thought["id"])
        if tid in have:
            skipped += 1
            continue
        try:
            embedding = _embed(thought["content"], ollama, model)
        except Exception as exc:
            log(f"  [{i}/{len(vault)}] SKIP embed failed: {str(exc)[:80]}")
            skipped += 1
            continue
        embedding_str = json.dumps(embedding)
        metadata_str = json.dumps(thought.get("metadata") or {})
        created = thought.get("created_at") or "now()"
        updated = thought.get("updated_at") or "now()"
        created_sql = "now()" if created == "now()" else f"{_sql_quote(str(created))}::timestamptz"
        updated_sql = "now()" if updated == "now()" else f"{_sql_quote(str(updated))}::timestamptz"
        sql = f"""
INSERT INTO public.thoughts (id, content, embedding, metadata, created_at, updated_at)
VALUES (
  {_sql_quote(tid)}::uuid,
  {_sql_quote(thought["content"])},
  '{embedding_str}'::vector,
  {_sql_quote(metadata_str)}::jsonb,
  {created_sql},
  {updated_sql}
)
ON CONFLICT (id) DO NOTHING;
"""
        result = subprocess.run(
            ["podman", "exec", db, "psql", "-U", "postgres", "-c", sql],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            log(f"  [{i}/{len(vault)}] ERROR: {result.stderr.strip()[:80]}")
            skipped += 1
            continue
        if "INSERT 0 1" in result.stdout:
            inserted += 1
            log(f"  [{i}/{len(vault)}] Restored {tid[:8]}…")
        else:
            skipped += 1
    log(f"Pull done. Inserted: {inserted}, Skipped: {skipped}")
    return 0


def main(argv: list[str]) -> int:
    args = [a for a in argv if a != "--hook"]
    if "--hook" in argv:
        os.environ["BRAIN_SYNC_HOOK"] = "1"
    if not args:
        die("usage: brain-sync.sh [--hook] pull|push|status")
    cmd = args[0]
    if cmd == "status":
        return cmd_status()
    if cmd == "push":
        return cmd_push()
    if cmd == "pull":
        return cmd_pull()
    die(f"unknown command: {cmd}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
