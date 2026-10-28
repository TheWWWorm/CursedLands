#!/bin/sh
# Quick remake-only check of every quest Kel's revival depends on: the
# Rod of Life fortune and fragment chains, their purchase orders, map startup
# scripts, departures, hand-offs and the rescue. Programs run in parallel
# (JOBS=auto: by CPU threads and free memory; or a number).
set -u
suite=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output=${1:?usage: run_lia_kel.sh NEW_OUTPUT_DIRECTORY}
: "${BASE_GAME:?owned base-game directory required}"
: "${ASTRAL_GAME:?owned patched Lost in Astral directory required}"
: "${GODOT:?Godot executable required}"
exec "${PYTHON:-python3}" "$suite/gameplay.py" --game-dir "$BASE_GAME" --astral-dir "$ASTRAL_GAME" \
    --godot "$GODOT" --out "$output" --display headless --no-original --jobs "${JOBS:-auto}" \
    --case lia_kel_ --case lia_fragment_first_entry
