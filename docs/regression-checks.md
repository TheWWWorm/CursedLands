# Focused checks for recurring reports

Use this selection before accepting changes near recent campaign/UI repairs.
[The manifest](../tools/regressions.json) records each behavior, issue links,
campaign, renderer requirement and minimum assertion count. It supplements the
[full gameplay suite](gameplay-testing.md); it does not certify every closed issue.

```sh
python3 tools/check_regressions.py \
  --engine /absolute/path/to/godot \
  --base-data /absolute/path/to/owned/base-game \
  --astral-data /absolute/path/to/owned/lost-in-astral \
  --output /absolute/path/to/new-results

# Real OpenGL checks, automatically submitted to GPU Lab on this workstation.
python3 tools/check_regressions.py --tier rendered \
  --engine /absolute/path/to/godot \
  --base-data /absolute/path/to/owned/base-game \
  --texts-en /absolute/path/to/english/texts.res \
  --texts-ru /absolute/path/to/russian/texts.res \
  --texts-de /absolute/path/to/german/texts.res \
  --output /absolute/path/to/new-rendered-results

# List or select individual cases. Multiple --only arguments combine.
python3 tools/check_regressions.py --tier all --list
python3 tools/check_regressions.py --engine /path/to/godot \
  --base-data /path/to/base-game --only attack_path_current_target \
  --only recent_character_controls --output /path/to/new-focused-results
```

The runner creates a new profile per case with mouse confinement disabled, FPS
visible, all three audio volumes zero and networking discovery disabled. It uses
the shared gameplay bootstrap to confirm the actual campaign, script, profile
and display. A rendered case cannot become a headless pass. The normal 30 FPS cap
is supplied; legacy fixtures may explicitly choose a different cap.

Every case requires exactly one named completion result, its minimum assertion
count, no failed assertions, a successful process exit and no script/game errors.
The existing full-suite summary parser is reused. The exact GPU Lab X11 missing
EDID refresh-rate diagnostic is retained separately; other errors still fail.
Missing required archives are setup failures. Output includes logs, generated
screenshots, source/engine/test hashes, commands and a JSON result after each case.
Results are never overwritten. This command runs synchronously when invoked; it
does not install a scheduler or configure remote CI.

Eleven previously unregistered headless scripts, including the live attack-path,
corpse-memory, trap-target, posture and character-control checks, are now also in
the full gameplay catalog. The multilingual rendered group remains in this
focused manifest because it requires separate original localized archives.

Every issue or bug fix and every feature addition or change MUST include a
registered regression test in the same change. Run it and related existing checks.
A fix must include a test that fails against the unfixed behavior.

Mechanism, prison-wall and Autochess checks also cover distant object teleports,
deferred topology labels, severe timing overload, reserve rearrangement, first-click
rewards, original deer cast origins and combat balance. Supply `--astral-data`
for the LiA recruits even when the test launches the base campaign. The full
gameplay runner uses `--astral-dir`; catalog entries declare their companion
archives in `extra_data` and reference their roots by campaign ID in arguments.
The [follow-up evidence](validation/mechanisms-autochess-2026-10-25/README.md)
distinguishes original replay, regression assertions and performance/balance fixtures.

For another recurring report, preserve its exact trigger as an assertion: for
example, a running target as well as a stationary one; unfinished as well as
completed investigations; a neutral trap neighbor as well as a hostile victim;
host and guest; and repeated load rather than only initial entry. When repairing
a failure, run the new check against the failing production build before the fix
when practical. Keep expected baseline failures separate from acceptance results.
Register the check in a runnable selection and record required data and limits.

The [October 25 audit](validation/regression-audit-2026-10-25/README.md) links the
tested behaviors and remaining gaps. Native Windows driver/frame-generation,
Android, internet co-op and full campaign playthroughs remain separate qualification
work; headless assertions do not replace them. The supplied load-crash path has
its own [Windows/Wine D3D12 repeated-load protocol](validation/load-crashes-cursor-2026-10-25/README.md).
