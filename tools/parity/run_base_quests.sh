#!/bin/sh
# Base-campaign completion routes and independently captured original outcomes.
set -u
suite=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output=${1:?usage: run_base_quests.sh NEW_OUTPUT_DIRECTORY}
: "${BASE_GAME:?owned base-game directory required}"
: "${GODOT:?Godot executable required}"
python=${PYTHON:-python3}
mkdir -p "$(dirname -- "$output")" || exit 2
mkdir "$output" || exit 2
status=0
if "$python" "$suite/gameplay.py" --game-dir "$BASE_GAME" --godot "$GODOT" \
    --out "$output/gameplay" --display headless --case base_campaign_ \
    --case side_quest_lifecycle --case lever_transition_save; then
    :
else
    status=$?
fi
if "$python" "$suite/checkpoints.py" run --game-dir "$BASE_GAME" --godot "$GODOT" \
    --name base_ --work-dir "$output/original-checkpoints"; then
    :
else
    code=$?
    if [ "$code" -gt "$status" ]; then status=$code; fi
fi
exit "$status"
