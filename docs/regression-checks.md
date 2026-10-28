# Focused checks for recurring reports

Use this selection before accepting changes near recent campaign/UI repairs.
[The manifest](../tools/regressions.json) records each behavior, issue links,
campaign, renderer requirement and minimum assertion count. It supplements the
[full gameplay suite](gameplay-testing.md); it does not certify every closed issue.

`script_expression_native` requires the rebuilt terrain extension. It compares
native and script evaluation, live variables/objects/levers, float32 boundaries,
RNG, lazy forms and side effects, including an original-game Wine fixture.
It also covers native `GroupSize`, `IsDead`, `UnitSee`, `GroupSee`, `GroupHas`
and `GroupCross`: lazy sighting forms, watcher order, looted/freed/derived units,
malformed shapes and kernels without the unit class. Their Foothills
measurements are in [the worker CPU validation](validation/foothills-worker-cpu-2026-10-27.md).
Related scheduler, clock, quest and lever checks and CPU measurements are in
[the CPU traversal validation](validation/cpu-traversal-2026-10-25/README.md).
`picking_retained` also requires the rebuilt extension and compares fused
mechanism bounds with the existing native and scalar paths, including live
morph/transform changes, clipping and unsupported-geometry fallbacks.
`picking_figures` checks the actor batch against the ordered per-part rectangles
and union, including authored poses, visibility and older-library fallback.

For dense PT city traversal, select `path_trace_motion_cost`,
`raytrace_topology_budget`, `raytrace_dense_scene`, `path_trace_motion`,
`path_trace_topology`, `raytrace_source_cache`, `water_raytrace_rebuild`,
`path_trace_shadow_motion`, `water_raytrace_live`, `path_trace_history_handoff`
and `revive_overlay_picking`. `dar_leanos_route` additionally requires LiA data
and follows fixed first-person waypoints with live solo authority. Its normal
30 FPS cap is for inspection; `--dar-benchmark` removes the cap for an isolated
GPU Lab heavy benchmark. Timing and negative controls are recorded in
[the Dar Leanos validation](validation/dar-leanos-2026-10-25/README.md).
`dar_leanos_standard_route` follows those same waypoints at Very High standard
rendering, including soft ground and mirror water. It uses
`--zone-route-standard`; the existing PT case retains its PT/NRD assertions.

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
and display. Headless checks use Safe rendering-thread mode, matching the campaign
and Autochess authority workers; rendered checks retain the package's renderer
thread settings. A rendered case cannot become a headless pass. The normal 30 FPS cap
is supplied; legacy fixtures may explicitly choose a different cap.

`path_trace_water` and `path_trace_water_live` explicitly select Forward+ because their hardware ray-tracing transport is unavailable in OpenGL. The runner unit suite checks these registered commands; the water options layout remains a separate UI check.

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

For slow save loading, select `save_load_render_cache` and
`save_load_render_cache_raster`. Both reload through the real authority worker;
they check texture reuse and fresh world ownership, and the PT case also checks
shared trace/NRD programs, private denoising history and final program disposal.
`authority_terrain_loading` compares the actual simulation-only map with a
presentation map across four original zones: terrain arrays, water changes,
object floors and all eight navigation classes must match, with no terrain
meshes or textures allocated by the authority. `terrain_cliff_reuse` covers
exact rock/snow geometry, input invalidation, isolated mutable state and cache
bounds. `terrain_color_loading` compares concurrent native bakes with serial
pixels, checks temporary image memory and preserves the live-streaming limit.
`terrain_cliff_disk` and `terrain_cliff_disk_rendered` drop process-local state
and check persisted rock/snow geometry, exact uploaded pixels, content-key
binding, corrupt-file recovery and disk limits. `shader_warmup_loading` counts
real render-thread draws and checks that revealed source meshes require no new
draw pipelines; every progress advance must still follow four completed draws.
`terrain_color_reuse` and `terrain_color_reuse_compatibility` exercise native
baking, changed inputs, current-world uniforms and bounded eviction. Related
cases include `terrain_color_native`, `terrain_color_lifecycle`,
`path_trace_nrd_device`, `path_trace_recenter_programs`,
`path_trace_loading_recenter`, `path_trace_retirement` and
`raytrace_retirement_budget`. The optional `tools/benchmarks/save_loading.gd`
records entry, first worker load and subsequent load times; use a GPU Lab heavy
job and serialize comparisons on the same assigned GPU. See the
[loading investigation](validation/loading-performance-2026-10-26/README.md).

`shader_warmup_depth_pass` switches the real main-viewport SSAO/depth pass
under forced and deferred loading, then reveals and moves hidden geometry.
It requires no new draw pipeline and reuses the paired preparation after PT
activation. `shader_warmup_formats` verifies small representatives retain the
full vertex layout of large indexed/compressed/custom/bone meshes without
changing their source. `terrain_shader_selection` checks one selected program
on fresh terrain and all 16 live water-option combinations against the old
final shader composition. `loading_worker_budget` holds real background jobs
to verify the four-thread pool allows two while retaining urgent capacity.
`terrain_color_render_thread` occupies the other workers and makes the render
worker wait cooperatively: native terrain bakes must stay off that worker,
produce exact pixels, keep the two-job bound and join during teardown.

Related `water_current`, `water_caustics` and `water_wave_render` checks cover
analytic current parity, live caustic receivers/clocks and rendered wakes.
The soft-ground caustic fixture uses zone11's authored snow and adjacent water;
zone15's tropical shore ceased to be eligible when deformation became snow-only.
No ground types, effects or pixel assertions are substituted. The fresh-load
and immediate-traversal comparison is documented in the
[hitch investigation](validation/fresh-loading-hitch-2026-10-27/README.md).

`wisp_loading` exercises the real Autochess recruitment card and combat meshes
after opening preparation, including all three native wisp forms. It requires
completed preview draws, no first-use draw/surface/mesh compilation, independent
crystal phases, shader invalidation, cancellation, re-entry and synchronous
preparation beneath a hidden campaign HUD. Related registered checks are
`wisp_native_callbacks`, `wisp_combat`, `wisp_visibility` and `wisp_visibility_gl`.
`wisp_loading_lia` checks the distinct LiA catalog, where the base Autochess
roster is unavailable: forced and deferred loading skip the absent wisp without
creating a viewport, marking unrendered content ready or retaining a cover.
The arena progress fixture waits for the actual first covered image before
capturing it; its required captures and exact pixel thresholds are unchanged.

The [October 25 audit](validation/regression-audit-2026-10-25/README.md) links the
tested behaviors and remaining gaps. Native Windows driver/frame-generation,
Android, internet co-op and full campaign playthroughs remain separate qualification
work; headless assertions do not replace them. The supplied load-crash path has
its own [Windows/Wine D3D12 repeated-load protocol](validation/load-crashes-cursor-2026-10-25/README.md).

The first D3D12 main menu after an update with a temporal mode selected has a
native Windows runner. It refuses Wine; a Proton reproduction on the
integration workstation is supplementary evidence only:

```powershell
powershell -ExecutionPolicy Bypass -File tools\run_native_d3d12_cold_start.ps1 `
  -Package C:\path\to\new-windows-package -SeedPackage C:\path\to\previous-release `
  -OriginalGame C:\path\to\owned\base-game
```

For DLSS (with PT and frame generation), TAA and FSR 2, the previous release
first opens the menu in a new profile with the same settings. The package under
test must then present the menu within 60 s of process start, with no frame
longer than 20 s, keep drawing while the shaders prepare, and finally draw the
mode (renderer frame counters, plus DLSS evaluations). A process that never
reports is killed after 240 s. Unfixed 1.34.0 fails every mode; see
[the investigation](validation/d3d12-cold-menu-2026-10-28/README.md).

Temporal character motion is registered in both runners as `unit_temporal_motion`.
The asset-free engine camera contract is registered with Python unittest discovery:

```sh
python3 -m unittest discover -s tools/tests -p test_dlss_camera_contract.py -v
```

This checks the committed patch stack against independent projection math and its
unfixed negative control. It does not replace native Windows DLSS-G testing.

The modding texture tools are covered by asset-free unittest modules:

```sh
python3 -B -m unittest discover -s tools/tests -p 'test_export_textures.py' -v
python3 -B -m unittest discover -s tools/tests -p 'test_package_mod.py' -v
```

`test_export_textures.py` checks DXT1/DXT3/PNT3/raw decoding against the game's
rounding, lossless PNG output, the package folder layout and preservation of
edited images. Full-data parity with the game's decoder is recorded in
[the texture export validation](validation/texture-export-2026-10-28.json).

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

`worker_rate_presentation` and its rendered variant cover a solo authority that
cannot sustain fast speed ([#119](validation/issue-119-worker-rate-2026-10-27.md)).
The manifest passes `--ei-simulation-load-ms=30`; LocalHost forwards it to the
worker, which waits that long after each logic tick to emulate a slower CPU.
Normal speed must remain exact. At fast speed the dial, the requested rate and
the saved speed stay fast, while the owner presents the achieved rate and the
visible Eagle Sight counter is not pulled back by snapshots.

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
The runner stages test scripts, nested fixture data and their benchmark helpers
with the original relative directory layout, records the PCK hash and omits the
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
Their route selector checks authored terrain and continuous body sweeps separately,
matching keyboard steering when actors overlap. `direct_movement_route_fixture`
checks that escape on a loaded map alongside the authority's existing collision,
input, stamina and interaction regressions.
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

For standalone web releases, run `python3 tools/check_web_release.py /path/to/CursedLands-VERSION-web.zip` before upload. It requires the complete committed public wiki and compares every file byte. `python3 -B -m unittest tools.tests.test_web_release` covers omitted, partial, changed and complete bundles.

Run `python3 -B -m unittest tools.tests.test_wiki_localization` when changing public wiki translation inputs. It checks that the Lost in Astral crawl tutorial uses the reviewed harpy translation rather than the different base-game ogre text.

Run `node tools/tests/wiki_art.mjs` when changing public wiki artwork or categories. It checks that failed or absent illustrations resolve to an existing fallback for every published entry in both campaigns and all three languages.
