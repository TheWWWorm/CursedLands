#!/bin/sh
# One entry point for real-original checkpoints and remake quest passability.
set -u
suite=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output=${1:?usage: run_lia_quests.sh NEW_OUTPUT_DIRECTORY}
: "${BASE_GAME:?owned base-game directory required}"
: "${ASTRAL_GAME:?owned patched Lost in Astral directory required}"
: "${GODOT:?Godot executable required}"
python=${PYTHON:-python3}
mkdir -p "$(dirname -- "$output")" || exit 2
mkdir "$output" || exit 2
status=0
if "$python" "$suite/gameplay.py" --game-dir "$BASE_GAME" --astral-dir "$ASTRAL_GAME" \
    --godot "$GODOT" --out "$output/gameplay" --display headless --jobs "${JOBS:-auto}" \
    --case lia_kel_ --case lia_campaign_ --case lia_fragment_first_entry --case use_callback_orders \
    --case lia_revenge_return --case lia_slave_lists_return \
    --case lia_tomb_exit --case zone7_arrival; then
    :
else
    status=$?
fi
if "$python" "$suite/checkpoints.py" run --astral-dir "$ASTRAL_GAME" --godot "$GODOT" \
    --name lia_ --work-dir "$output/original-checkpoints"; then
    :
else
    code=$?
    if [ "$code" -gt "$status" ]; then status=$code; fi
fi
exit "$status"
