import sys
import unittest
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


class TestThoughtsMerge(unittest.TestCase):
    def test_only_local_kept(self):
        out = merge_thoughts([], [_t("a", "local", "2026-09-19T10:00:00Z")])
        self.assertEqual([x["id"] for x in out], ["a"])

    def test_only_vault_kept(self):
        out = merge_thoughts([_t("b", "vault", "2026-09-19T10:00:00Z")], [])
        self.assertEqual([x["id"] for x in out], ["b"])

    def test_newer_local_wins(self):
        vault = [_t("a", "old", "2026-09-19T10:00:00Z")]
        local = [_t("a", "new", "2026-09-19T12:00:00Z")]
        out = merge_thoughts(vault, local)
        self.assertEqual(out[0]["content"], "new")

    def test_newer_vault_wins(self):
        vault = [_t("a", "vault-new", "2026-09-19T12:00:00Z")]
        local = [_t("a", "local-old", "2026-09-19T10:00:00Z")]
        out = merge_thoughts(vault, local)
        self.assertEqual(out[0]["content"], "vault-new")

    def test_equal_timestamp_local_wins(self):
        ts = "2026-09-19T10:00:00Z"
        out = merge_thoughts([_t("a", "vault", ts)], [_t("a", "local", ts)])
        self.assertEqual(out[0]["content"], "local")

    def test_union_two_machines(self):
        vault = [_t("apple", "morning", "2026-09-19T10:00:00Z")]
        local = [_t("fedora", "afternoon", "2026-09-19T16:00:00Z")]
        ids = {x["id"] for x in merge_thoughts(vault, local)}
        self.assertEqual(ids, {"apple", "fedora"})

    def test_validate_rejects_empty(self):
        with self.assertRaises(ValueError) as ctx:
            validate_envelope("")
        self.assertTrue("empty" in str(ctx.exception).lower() or "invalid" in str(ctx.exception).lower())

    def test_validate_version2_roundtrip(self):
        thoughts = [_t("a", "x", "2026-09-19T10:00:00Z")]
        env = build_envelope(thoughts, "travis-mac-apple", "2026-09-19T10:00:00Z")
        self.assertEqual(env["version"], 2)
        self.assertEqual(env["thought_count"], 1)
        self.assertEqual(env["machine"], "travis-mac-apple")
        parsed = validate_envelope(env)
        self.assertEqual(parsed[0]["id"], "a")

    def test_validate_rejects_count_mismatch(self):
        env = build_envelope([_t("a", "x", "2026-09-19T10:00:00Z")], "travis-fedora")
        env["thought_count"] = 99
        with self.assertRaises(ValueError):
            validate_envelope(env)

    def test_does_not_dedupe_by_content(self):
        vault = [_t("id1", "same text", "2026-09-19T10:00:00Z")]
        local = [_t("id2", "same text", "2026-09-19T11:00:00Z")]
        out = merge_thoughts(vault, local)
        self.assertEqual(len(out), 2)


if __name__ == "__main__":
    unittest.main()
