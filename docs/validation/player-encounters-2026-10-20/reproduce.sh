#!/bin/sh
set -eu
audit_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$audit_dir/../../.." && pwd)
output=${1:?"usage: reproduce.sh NEW_OUTPUT_DIRECTORY [runner filters]"}
shift
exec "${PYTHON:-python3}" "$repo_dir/tools/parity/gameplay.py" \
  --game-dir "${BASE_GAME:?'Set BASE_GAME to the owned original installation'}" \
  --astral-dir "${ASTRAL_GAME:?'Set ASTRAL_GAME to the owned Astral installation'}" \
  --godot "${GODOT:?'Set GODOT to the Godot executable'}" \
  --render-display "${RENDER_DISPLAY:?'Set RENDER_DISPLAY to a private X server'}" \
  --replay-selection "$audit_dir/selection.json" \
  --with-original --out "$output" "$@"
