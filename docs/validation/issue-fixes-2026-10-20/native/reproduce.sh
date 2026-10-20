#!/usr/bin/env bash
set -euo pipefail
here="$(cd -- "$(dirname -- "$0")" && pwd)"
repo="$(cd -- "$here/../../../.." && pwd)"
: "${BASE_GAME:?Set BASE_GAME to the original base-game directory}"
: "${GODOT:?Set GODOT to the Godot executable}"
output="${1:?Supply a new output directory}"
shift
inputs="$(mktemp)"
trap 'rm -f -- "$inputs"' EXIT
gzip -dc "$here/inputs.json.gz" > "$inputs"
"${PYTHON:-python3}" "$repo/tools/parity/run.py" \
  --game-source "$repo/game" --game-dir "$BASE_GAME" --godot "$GODOT" \
  --replay-inputs "$inputs" --repeat 2 --out "$output" "$@"
