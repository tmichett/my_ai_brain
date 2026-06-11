# Cursor Canvases

Interactive React diagrams that open beside the chat in **Cursor IDE**.

## Course build workflow

File: [`course-build-workflow.canvas.tsx`](course-build-workflow.canvas.tsx)

### One-time setup

From the repo root:

```bash
./scripts/setup-canvas-sdk.sh
```

This symlinks the canvas into Cursor's project folder and copies the `cursor/canvas` type stubs.

### Open in Cursor

1. Open **`/Users/travis/Github/my_ai_brain`** as a Cursor workspace (File → Open Folder).
2. Click [`course-build-workflow.canvas.tsx`](course-build-workflow.canvas.tsx) in the file tree, or use **Open Canvas** from the chat link.
3. The canvas renders beside the chat with scroll, collapsible sections, and the full workflow diagram.

### Standalone (no Cursor)

For a browser-based interactive version that runs anywhere:

```bash
cd visualizations/course-build-workflow
npm install
npm run dev
```

Open http://localhost:5173

### Static PNG for Obsidian

Pre-rendered assets live in [`../assets/diagrams/`](../assets/diagrams/). Regenerate:

```bash
uv run python scripts/generate-course-build-workflow-diagram.py
```

Copies PNG into the Obsidian vault at `AI Brain/assets/course-build-workflow.png`.
