# Sustained hold accounting replay

CPU-only Godot 4.7 headless execution: **10 checks passed, exit 0**.
`replay.gd` embeds the exact accounting branch extracted from the current
`path_trace_sustained.gd`; `command.json` records its source lines and hashes.
No GPU qualification or production changes were made by this replay.

The captured final-02 failure counted 2229 rendered frames, all matching output,
with no state boundaries, zero fallback/mismatch frames and zero rebuilding
frames. Its 288 resets were caused by zero frame-counter deltas entering the
same branch as real output mismatches. The corrected branch records those
wakeups separately, retains the stable interval and gives zero time/frame
credit. Actual mismatch, device and generation replacement still reset; the
100ms-per-actual-frame cap and hard wall deadline remain unchanged.

The replay checks duplicate observation, 288 consecutive duplicate callbacks,
continued counting on the next actual frame, real mismatch with zero frames,
device replacement, generation replacement, and one/two-frame stall caps.
`results.json` and `run.log` contain the passing result. `initial-parse.log`
retains a failed first harness launch caused by mixed indentation in generated
wrapper code; only that wrapper indentation was corrected before the passing
replay. The source fixture was not changed during this replay.
