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
    """Return thoughts. Missing file → []. Empty/invalid → ValueError."""
    from pathlib import Path

    p = Path(path)
    if not p.exists():
        return []
    raw = p.read_bytes()
    if len(raw) == 0:
        raise ValueError("empty envelope")
    return validate_envelope(raw.decode("utf-8"))
