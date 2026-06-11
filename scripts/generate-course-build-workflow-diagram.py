#!/usr/bin/env python3
"""Generate course-build-workflow SVG + PNG for Obsidian."""

from __future__ import annotations

import shutil
import subprocess
import textwrap
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
OUT_DIR = REPO / "assets" / "diagrams"
VAULT_ASSETS = Path(
    "/Users/travis/Documents/MBP-M3-RH/Obsidian-Work-Vault/Obsidian-Work/AI Brain/assets"
)

NODES = [
    ("start", "New course repo", "RedHatTraining/{SKU}", "repo", 1),
    ("create-inv", "create_inventory", "profile + rhelver", "doit", 1),
    ("scaffold", "Inventory scaffold", "inventory · group_vars · site.yml", "repo", 1),
    ("configure", "Configure course", "course.yml · SSL_VMs", "dev", 2),
    ("validate", "validate_inventory", "schema vs profiles.yml", "doit", 2),
    ("ssl", "get_ssl_certs", "DLE-Web → files/ssl/", "doit", 2),
    ("heat", "dle-doit pipeline", "Heat templates", "doit", 3),
    ("commit", "git commit & push", "PEMs · requirements.yml", "repo", 3),
    ("project-sync", "AAP Project sync", "GitHub → /runner/project/", "aap", 4),
    ("ee", "Execution Environment", "Job template + EE", "aap", 4),
    ("site", "site.yml", "ansible-playbooks-novello", "aap", 5),
    ("components", "dle.components", "features · IdM SSL", "lab", 5),
    ("course-plays", "Course playbooks", "upgrade · VS Code · clean", "lab", 5),
    ("aap-install", "AAP install", "optional · custom_ca_cert", "lab", 6),
    ("done", "Classroom ready", "TLS · features · content", "lab", 6),
]

EDGES = [
    ("start", "create-inv"), ("create-inv", "scaffold"), ("scaffold", "configure"),
    ("configure", "validate"), ("configure", "ssl"), ("validate", "heat"),
    ("ssl", "commit"), ("heat", "commit"), ("commit", "project-sync"),
    ("project-sync", "ee"), ("ee", "site"), ("site", "components"),
    ("components", "course-plays"), ("course-plays", "aap-install"), ("aap-install", "done"),
]

PHASES = [
    (1, "Scaffold", "create_inventory"),
    (2, "Configure", "inventory + SSL PEMs"),
    (3, "Artifacts", "Heat + git push"),
    (4, "Controller", "GitHub + EE"),
    (5, "Provision", "site.yml"),
    (6, "Complete", "classroom live"),
]

LANE_COLORS = {
    "dev": "#3a3a3c",
    "repo": "#2c3440",
    "doit": "#3d3528",
    "aap": "#1e3a5f",
    "lab": "#2a3530",
}
ACCENT = "#388bfd"
TEXT = "#e6edf3"
TEXT_DIM = "#8b949e"
STROKE = "#484f58"
BG = "#0d1117"

NW, NH, RGAP, NGAP, PAD = 150, 58, 48, 16, 32
PHASE_H = 36


def layout_horizontal() -> tuple[dict[str, tuple[float, float, int]], list[tuple[str, str]]]:
    """Assign ranks via longest path; place nodes left-to-right."""
    ids = [n[0] for n in NODES]
    adj: dict[str, list[str]] = {i: [] for i in ids}
    rev: dict[str, list[str]] = {i: [] for i in ids}
    for a, b in EDGES:
        adj[a].append(b)
        rev[b].append(a)

    rank: dict[str, int] = {i: 0 for i in ids}
    changed = True
    while changed:
        changed = False
        for a, b in EDGES:
            if rank[b] < rank[a] + 1:
                rank[b] = rank[a] + 1
                changed = True

    by_rank: dict[int, list[str]] = {}
    for nid in ids:
        by_rank.setdefault(rank[nid], []).append(nid)

    positions: dict[str, tuple[float, float, int]] = {}
    x = PAD
    for r in sorted(by_rank):
        col = by_rank[r]
        col_h = len(col) * NH + (len(col) - 1) * NGAP
        y_start = PAD + PHASE_H + max(0, (col_h - NH) / 2) if len(col) == 1 else PAD + PHASE_H
        if len(col) == 1:
            positions[col[0]] = (x, y_start, r)
        else:
            for i, nid in enumerate(col):
                positions[nid] = (x, PAD + PHASE_H + i * (NH + NGAP), r)
        x += NW + RGAP
    return positions, EDGES


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def wrap(text: str, width: int = 18) -> list[str]:
    return textwrap.wrap(text, width=width) or [""]


def build_svg() -> str:
    pos, edges = layout_horizontal()
    max_x = max(p[0] for p in pos.values()) + NW + PAD
    max_y = max(p[1] for p in pos.values()) + NH + PAD + 120
    w, h = int(max_x), int(max_y)

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">',
        f'<rect width="100%" height="100%" fill="{BG}"/>',
        f'<text x="{PAD}" y="28" fill="{TEXT}" font-family="system-ui,sans-serif" font-size="20" font-weight="600">Course Build Workflow</text>',
        f'<text x="{PAD}" y="48" fill="{TEXT_DIM}" font-family="system-ui,sans-serif" font-size="12">dle-doit · Ansible inventory · Automation Controller · Execution Environment</text>',
    ]

    # Phase headers
    rank_x: dict[int, float] = {}
    for nid, (x, _y, r) in pos.items():
        rank_x.setdefault(r, x)
    for n, title, sub in PHASES:
        if n - 1 not in rank_x:
            continue
        rx = rank_x[n - 1]
        lines.append(f'<text x="{rx + NW/2}" y="{PAD + PHASE_H - 8}" fill="{TEXT_DIM}" font-family="system-ui,sans-serif" font-size="11" font-weight="600" text-anchor="middle">{esc(title)}</text>')
        lines.append(f'<text x="{rx + NW/2}" y="{PAD + PHASE_H + 4}" fill="{TEXT_DIM}" font-family="system-ui,sans-serif" font-size="9" text-anchor="middle" opacity="0.8">{esc(sub)}</text>')

    node_map = {n[0]: n for n in NODES}

    # Edges
    for a, b in edges:
        x1, y1, _ = pos[a]
        x2, y2, _ = pos[b]
        sx, sy = x1 + NW, y1 + NH / 2
        tx, ty = x2, y2 + NH / 2
        mx = (sx + tx) / 2
        lines.append(
            f'<path d="M {sx} {sy} C {mx} {sy}, {mx} {ty}, {tx} {ty}" fill="none" stroke="{STROKE}" stroke-width="1.5" marker-end="url(#arrow)"/>'
        )

    lines.append(
        f'<defs><marker id="arrow" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">'
        f'<polygon points="0 0,8 3,0 6" fill="{STROKE}"/></marker></defs>'
    )

    for nid, (x, y, _r) in pos.items():
        _id, label, detail, lane, _phase = node_map[nid]
        fill = ACCENT if nid == "done" else LANE_COLORS.get(lane, "#333")
        fg = BG if nid == "done" else TEXT
        lines.append(f'<rect x="{x}" y="{y}" width="{NW}" height="{NH}" rx="6" fill="{fill}" stroke="{STROKE}"/>')
        lines.append(f'<text x="{x + 8}" y="{y + 18}" fill="{fg}" font-family="system-ui,sans-serif" font-size="11" font-weight="600">{esc(label)}</text>')
        for i, ln in enumerate(wrap(detail, 20)[:2]):
            lines.append(f'<text x="{x + 8}" y="{y + 34 + i * 12}" fill="{fg if nid == "done" else TEXT_DIM}" font-family="system-ui,sans-serif" font-size="9">{esc(ln)}</text>')

    # Legend
    ly = h - 90
    lines.append(f'<text x="{PAD}" y="{ly}" fill="{TEXT}" font-family="system-ui,sans-serif" font-size="11" font-weight="600">Legend</text>')
    legend = [("Developer", "dev"), ("Course repo", "repo"), ("dle-doit", "doit"), ("Automation Controller", "aap"), ("Lab targets", "lab")]
    lx = PAD
    for name, lane in legend:
        lines.append(f'<rect x="{lx}" y="{ly + 8}" width="10" height="10" rx="2" fill="{LANE_COLORS[lane]}" stroke="{STROKE}"/>')
        lines.append(f'<text x="{lx + 16}" y="{ly + 17}" fill="{TEXT_DIM}" font-family="system-ui,sans-serif" font-size="10">{esc(name)}</text>')
        lx += 130

    # Footer panels
    fy = h - 52
    panels = [
        "Inventory: classroom/ansible-playbooks-novello/ · inventory.yml · group_vars · files/ssl/",
        "Controller: GitHub project sync · EE · collections/requirements.yml at repo root · inventory_dir for PEMs",
    ]
    for i, p in enumerate(panels):
        lines.append(f'<text x="{PAD}" y="{fy + i * 14}" fill="{TEXT_DIM}" font-family="ui-monospace,monospace" font-size="9">{esc(p)}</text>')

    lines.append("</svg>")
    return "\n".join(lines)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    VAULT_ASSETS.mkdir(parents=True, exist_ok=True)
    svg_path = OUT_DIR / "course-build-workflow.svg"
    png_path = OUT_DIR / "course-build-workflow.png"
    vault_png = VAULT_ASSETS / "course-build-workflow.png"
    vault_svg = VAULT_ASSETS / "course-build-workflow.svg"

    svg = build_svg()
    svg_path.write_text(svg, encoding="utf-8")
    vault_svg.write_text(svg, encoding="utf-8")

    subprocess.run(
        ["rsvg-convert", "-w", "3200", "-f", "png", "-o", str(png_path), str(svg_path)],
        check=True,
    )
    vault_png.write_bytes(png_path.read_bytes())
    shutil.copy2(svg_path, vault_svg)

    print(f"Wrote {svg_path}")
    print(f"Wrote {png_path}")
    print(f"Wrote {vault_png}")


if __name__ == "__main__":
    main()
