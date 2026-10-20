#!/bin/sh
set -eu
output=${1:?"NEW_OUTPUT_DIRECTORY required"}
shift
exec /home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/venv/bin/python /home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/repo/tools/parity/gameplay.py --game-dir /home/llm2x/Documents/EI/inspection/extracted/app --game-source /home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/repo/game --godot /home/llm2x/.local/bin/godot-4 --seed 20261020 --replay-selection /home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/release-1.20.0/gameplay-rendered/selection.json --astral-dir /home/llm2x/Documents/EI/inspection/lost-in-astral/game --render-display :91 --out "$output" "$@"
