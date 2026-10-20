#!/bin/sh
set -eu
output=${1:?"usage: reproduce.sh NEW_OUTPUT_DIRECTORY [--case ID]"}
shift
exec /home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/repo/../venv/bin/python /home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/repo/tools/parity/run.py --game-dir /home/llm2x/Documents/EI/inspection/extracted/app --game-source /home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/repo/game --godot /home/llm2x/.local/bin/godot-4 --replay-inputs /home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/release-1.20.0/native/inputs.json --repeat 2 --out "$output" "$@"
