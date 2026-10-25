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

# Rendered checks, automatically submitted to GPU Lab on this workstation.
python3 tools/check_regressions.py --tier rendered \
  --engine /absolute/path/to/godot \
  --base-data /absolute/path/to/owned/base-game \
  --astral-data /absolute/path/to/owned/lost-in-astral \
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

Temporal character motion is registered in both runners as `unit_temporal_motion`.
The asset-free engine camera contract is registered with Python unittest discovery:

```sh
python3 -m unittest discover -s tools/tests -p test_dlss_camera_contract.py -v
```

This checks the committed patch stack against independent projection math and its
unfixed negative control. It does not replace native Windows DLSS-G testing.

The gameplay catalog also registers `effects/path_trace_material_receivers` as a
Forward+ rendered check. It explicitly asserts native unfiltered output before
measuring the PT receiver’s material boundary. DLSS output reconstruction has its
own evaluation and movement checks; it is not included in this raw receiver test.

The October 25 follow-up for [issues 113–116](validation/issues-113-116-2026-10-25/README.md)
adds `killing_posture_queue`, `backstab_hit_reaction`, `save_rename` and
`worker_travel_clock` to both runners. Save renaming also has rendered EN/RU/DE
cases in the focused manifest; `worker_travel_clock_rendered` measures the real
solo authority through the visible HUD. The clock test covers a restored fast
save, a stale owner cache, Ruins/Foothills travel, village return and a 5 FPS
owner. It asserts actual simulation seconds per wall second, not only the dial
or `Engine.time_scale`.

The [menu checks](validation/menu-patrol-text-2026-10-25/README.md) register
`menu_patrols_*`, `menu_alignment_*` and `menu_captions_*` for both campaigns,
plus the existing weather fixture as `menu_wind_ready`.
They exercise authored patrol routes, projected pole alignment at five window
sizes, and the original caption artwork in the main menu, actual paused Escape
menu and Options. Caption checks compare preserved glyphs and relief with the
owned archive and require better edge contrast than bilinear enlargement. The
EN/RU/DE runs select the remake UI language; painted captions continue to use
the supplied edition's own localized artwork.

Exported engines can be tested against their adjacent PCK with `--packaged`.
The runner stages the external fixtures, records the PCK hash and omits the
editor-only `--path`. Use the qualified custom runtime for ray-tracing checks;
the stock editor does not expose the project's native ray APIs. Rendered cases
may declare `rendering_method: forward_plus`; ordinary UI checks retain their
Compatibility default. Unsupported hardware is not a passing trace check.

The October 25 EI1 selection includes unindexed weather-cover geometry, repeated
LiA save loads in raster/PT modes, direct-light stability, incremental water
replacement, crash-report hover, clock resynchronization and a 90-second local
transport stall. Expected baseline
failures and measurements are recorded in
[the investigation](validation/ei1-2026-10-25/README.md). The LiA fixture accepts
`--save-fixture=/absolute/copied-save.sav` when launched directly; it copies that
save into its disposable profile before running two ordinary worker loads.

The LiA fixture also accepts `--lia-fg` in a Windows D3D12 runtime with NVIDIA FG
available. Each load must activate FG and increment the SDK presentation counter;
a requested setting alone does not pass. This hardware check is supplemental to
the portable registered raster/PT load cases.

`path_trace_shadow_motion` keeps receiver history valid while a small sun caster
moves twice. It checks the stationary umbra, old/new shadow response within
three frames, and agreement between full diffuse lighting and the terrain sun
AOV. It runs through the packaged Forward+ GPU runner.

`path_trace_zone_traversal_river` and `path_trace_zone_traversal_snow` load
authored Gipat and LiA terrain through the separate solo worker. They inject
keyboard movement through the production first-person controller, alternate
forward/downward views and camera pans, and require PT/native NRD and usable
controls throughout. They also check actual displacement, advancing simulation,
command acknowledgement, worker survival and a free cursor. They are capped
visual checks, not performance benchmarks or automated shimmer measurements.
The [ten-zone audit](validation/ei1-first-person-2026-10-25/README.md) includes
recordings, image review and the remaining city performance finding.

The shared fixture accepts `--zone-route-zone=ZONE`,
`--zone-route-save=/absolute/copied-save.sav`, and `--audit-out=/absolute/output`.
`--zone-route-fg` additionally requires a qualified NVIDIA Windows D3D12 runtime
and verifies both active FG and the SDK presentation counter during movement.
`--zone-route-peaceful` creates neutral initial diplomacy only for a synthetic
zone save; it retains actors, patrols and collisions. This supplemental visual
mode is not used by the registered cases or the supplied-save check. Every run
uses an isolated muted profile with FPS visible and the cursor free.
