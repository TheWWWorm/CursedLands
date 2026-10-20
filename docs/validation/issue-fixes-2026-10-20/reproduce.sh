#!/usr/bin/env bash
set -euo pipefail
here="$(cd -- "$(dirname -- "$0")" && pwd)"
repo="$(cd -- "$here/../../.." && pwd)"
: "${BASE_GAME:?Set BASE_GAME to the original base-game directory}"
: "${ASTRAL_GAME:?Set ASTRAL_GAME to the expansion directory}"
: "${GODOT:?Set GODOT to the Godot executable}"
: "${RENDER_DISPLAY:?Set RENDER_DISPLAY to an isolated rendering display}"
output="${1:?Supply a new output directory}"
shift
exec "${PYTHON:-python3}" "$repo/tools/parity/gameplay.py" \
  --game-source "$repo/game" --game-dir "$BASE_GAME" --astral-dir "$ASTRAL_GAME" \
  --godot "$GODOT" --render-display "$RENDER_DISPLAY" \
  --replay-selection "$here/selection.json" --out "$output" "$@"
