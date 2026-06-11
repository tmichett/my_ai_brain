#!/usr/bin/env bash
# Link my_ai_brain canvases into Cursor's managed project folder and install type stubs.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CANVAS_DIR="$REPO_ROOT/canvases"
CURSOR_PROJECT="$HOME/.cursor/projects/Users-travis-Github-my-ai-brain/canvases"
SOURCE_SDK="$HOME/.cursor/projects/Users-travis-Github-BI0000/canvases/node_modules"

mkdir -p "$CURSOR_PROJECT"

for f in course-build-workflow.canvas.tsx tsconfig.json; do
  ln -sf "$CANVAS_DIR/$f" "$CURSOR_PROJECT/$f"
done

if [[ -d "$SOURCE_SDK/cursor" ]]; then
  mkdir -p "$CANVAS_DIR/node_modules"
  rsync -a --delete "$SOURCE_SDK/cursor" "$CANVAS_DIR/node_modules/"
  if [[ -d "$SOURCE_SDK/@types" ]]; then
    rsync -a "$SOURCE_SDK/@types" "$CANVAS_DIR/node_modules/"
  fi
  rsync -a --delete "$CANVAS_DIR/node_modules/cursor" "$CURSOR_PROJECT/node_modules/" 2>/dev/null || {
    mkdir -p "$CURSOR_PROJECT/node_modules"
    rsync -a "$CANVAS_DIR/node_modules/cursor" "$CURSOR_PROJECT/node_modules/"
    [[ -d "$CANVAS_DIR/node_modules/@types" ]] && rsync -a "$CANVAS_DIR/node_modules/@types" "$CURSOR_PROJECT/node_modules/"
  }
  echo "Canvas SDK types installed from BI0000 canvases node_modules"
else
  echo "WARN: Cursor canvas SDK not found at $SOURCE_SDK — open any workspace with a canvas first, then re-run."
fi

echo "Linked canvases:"
echo "  $CURSOR_PROJECT/course-build-workflow.canvas.tsx -> $CANVAS_DIR/course-build-workflow.canvas.tsx"
echo ""
echo "Open /Users/travis/Github/my_ai_brain in Cursor and click the canvas file."
