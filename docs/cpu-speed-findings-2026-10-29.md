# CPU speed findings, 2026-10-29

Measurements and leads from the CPU-speed pass on branch
`perf/cpu-speed-20261029` (base `e380c4c6`). Everything here was measured but
not changed; each entry names the code to pick it up from. The path tracer
and ray tracing are out of scope by request. Evidence (profiles, logs) lives
in `local/validation/cpu-speed-20261029/` on the workstation.

Fixtures used throughout:

- Portal (`gz1h`, 415 units): `local/scratchpad/cpu-redesign-20261006/portal-user-save/lost_in_astral/quick.sav`, LiA data.
- Foothills (`gz3g`, 214 units): `local/validation/perf-worker-20261027/fixtures/fresh-foothills.sav`, base-game data (the save does not load under the LiA data path).
- Simulation profile: `tools/benchmarks/campaign_cpu.gd` with `--throughput-config=<cfg.json>` (`{"name","save","zone","units","ticks","profile","out"}`), 600 ticks.
- Worker frame probe (headless authority at 30 fps, like the solo worker): the `worker_frame_profile.gd` probe from the issue-119 work (`--save --rate --seconds --scopes --variant --census --fps --dump`).

## Done in this pass (for context)

A headless authority (the solo campaign's simulation worker) now sleeps the
presentation of actors it has not ticked for two logic steps
(`GameUnit._can_sleep_authority_presentation`, `GameWorld._step_hidden_presentations`).
Portal, worker at 1x and 30 fps, three runs each: CPU core share 0.46 → 0.38,
process time per frame 40.5 → 30.8 ms (summed `TIME_PROCESS` monitor), tick
rate unchanged. Regression `animation/authority_presentation_sleep`.

`UnitAI.player_perceive` skips the perception kernels when the observer's
notice cells hold nobody (`stealth/perception_empty_scan`), and a unit's
animation player holds only the tracks of its figure's parts
(`animation/animation_library_pruned`, item 7).

## 1. Script-driven perception dominates the Foothills tick

Foothills, 600 ticks, `profile_simulation` on (ms per tick; the profiler
itself adds ~1 ms, see item 5):

| scope | ms/tick | calls/tick |
| --- | --- | --- |
| world (whole tick) | 7.4–8.3 | 1 |
| script (`ScriptVM.tick`) | 3.7–4.0 | 1 |
| units (`GameUnit.tick` loop) | 3.0–3.3 | 1 |
| `vmtrig:VCheck#0#140` | 1.52 | 42 |
| `vmtrig:VCheck#0#176` | 0.35 | 42 |
| `aiplayer_perceive` | 1.8–2.0 | 68 |
| `ai_notice_candidates` | 0.74 | 65 |

`VCheck#0#140` is one trigger per NPC (42 copies, one `this` each):
`GroupSize(GroupCross(UnitSee(this), Heroes))` → `KillScript; VTriger#0#141(this)`.
Every copy is polled every tick (`ScriptVM.POLL` = one tick, `vm.gd:19`) and
cannot share the condition memo (different `this`). `GroupCross(UnitSee(..))`
takes the shortcut at `vm.gd:770-782` → `_sees_has` → `_noticed(w)` →
`UnitAI.player_perceive(w)` (`vm.gd:1612-1623`): a forced perception scan
per NPC per tick, which is where the 68 scans per tick come from (the AI's
own schedule, `unit.gd:1847`, is per tick only for player-motivation units).

Breakdown of one `player_perceive` call (Foothills, temporary scopes, µs per
call): drop pass 1.5; `_notice_candidates` 13.1 (11.4 inside its own scope);
`UnitQueryKernel.notice_candidates` 5.8; `PerceptionKernel.new_visible` 4.3;
accept loop 0.2; meta stores 0.3. 58 of 65 scans per tick end with **zero
candidates**, so the two native calls are pure call overhead there.

Leads, in order of expected value:

1. Done (`c94644d0`): `UnitAI.player_perceive` returns after the drop pass
   when `_notice_candidates` is empty. Measured without the profiler the two
   skipped kernel calls were only ~1.2 µs of a 4.5 µs cached empty scan
   (~0.1 ms per Foothills tick); the profiled figures above overstate small
   scopes (item 5). The remaining per-scan cost is the candidate refresh.
2. `_notice_candidates` (`ai.gd:1146-1160`) refreshes each unit's cell list
   every 8–11 ticks through `GameWorld.notice_units_near` (`world.gd:641`),
   about 7 refreshes per tick at ~90 µs each — most of the 0.74 ms. The
   refresh runs `_spatial_order()` and `UnitQueryKernel.near_cells`, then
   `_bucket_list_order`. A native `near_cells` that returns the list already
   in notice-cell order (the rank table `UnitAI.NOTICE_CELL_ORDER` is
   static) would remove the GDScript reorder; keep the original order
   (`docs/validation/notice-candidate-order-2026-10-28.md`).
3. The VM shortcut evaluates `_sees_has(watchers, x)` once per hero per copy;
   `_seen_memo` already shares the watcher's list within a tick. No further
   sharing is possible across copies without changing when a sighting is
   detected (the original polls every tick).

## 2. Parallel perception (multithreading candidate)

`PerceptionKernel::new_visible` (`game/src/native/source/perception_batch.h`)
is per observer and sequential. Its inputs are the `UnitSimulationState`
mirrors (pos, facing, dead, hidden, stance, action, proto, buffs) plus two
callbacks: `GameWorld.sight_ray` (`world.gd:514`, which is
`NavGrid.ray` → native `_ray_kernel.ray` when the native builder is present,
`nav_grid.gd:2813`) and the `UnitAI.can_notice_with` fallback for unusual
effect records. A tick-wide batch (`new_visible_batch(observers…)`) could
evaluate observers on `WorkerThreadPool` with the ray done natively and only
the fallback cases returned for sequential scripting, then apply results in
observer order (the side effects `suspect`, `call_for_help`,
`_notice_corpse` do not change any input of `visible()`; see the note at
`ai.gd:736`). Expected gain in Foothills is bounded by the native share of
the 1.8 ms (`new_visible` 0.28 ms + the ray calls inside it); item 1 is
cheaper and should come first. Determinism: results must not depend on
thread order (collect per observer, apply in order).

Other per-tick phases that are read-only per unit and could batch the same
way: `unit_do_move`/`unit_step_along_path` (1.4 ms per Foothills tick,
`NavGrid` path steps) — check whether the native nav kernel's step and
blocker queries (`UnitQueryKernel.step_blocker`) read anything a sibling's
move writes in the same tick before parallelising.

## 3. Worker presentation that still runs every frame

After the sleep change the worker still presents the ~43 awake Portal
actors every frame (`GameUnit._present_native_frame`, `unit.gd:4215`) and
their `EIUnitModel` animation players. Remaining frame cost at 30 fps was not
split further; the probe variants `off:EIUnitModel`, `off:GameUnit` and
`noanim` give the attribution (earlier numbers in
`local/validation/issue-119-20261027/`). Snapshot building
(`snap_ms_per_s` 22–25 ms per second in the probe) is the other fixed
per-frame cost of the worker (`Session`/`LocalHost` snapshot path).

## 4. Client-side frame cost

Measured with `client_frame_profile.gd` (real client + solo worker on GPU
Lab, Portal save, 2880×1800, Forward+, 10 s window): the client runs at
~111 fps with 5 actors on screen and ~9 ms process time per frame; it is
not presentation-bound in that view. The `off:GameUnit` subtraction variant
is invalid (fps fell to 66 and CPU rose: units without `_process` lose their
sleeping) — do not use it for attribution. What the player waits for in the
Portal is the zone load (item 7), not the frame.

Candidates for a denser view (a battle with 30+ actors on screen) remain
`GameUnit._process` → `_present_frame`, `EIUnitModel` animation, `NetSmooth`
placement (`world.gd:804`, native batch per frame), `UnitWounds`, and the
camera/UI scripts. The replica sleeping framework already covers off-screen
actors.

## 5. Profiler overhead

`GameWorld.profile_scope` (`world.gd:155`) allocates a `ProfileScope` with a
bound `Callable` per call; with ~400 scopes per tick the profiled Foothills
tick is ~1 ms (12%) slower than the plain one (`tick_ms.p50` 6.9 vs 7.5 ms).
Per-call numbers above are therefore upper bounds. A cheaper profiler
(explicit `started` timestamps, as `GameWorld._tick` already does for its
own sections) would make the small per-unit scopes trustworthy.

## 6. Unrelated defects met on the way

- `lia_weather_load_raster` (rendered): `record.cold` missing from a
  `cover_warmup_variants` warmup record → `biome_cover_mesh.gd:353`, then
  `Condition "p_arrays.size() != ARRAY_MAX"` at `terrain_details.gd:663`.
  Reproduces on the fixed and unfixed surface-map trees; not a perception or
  CPU item.
- `terrain_surface_live`'s "traced sand prepares" needs the patched engine's
  ray-tracing API (`docs/path-tracing-qualification.md`); it cannot pass on
  the stock 4.7 editor used for these runs. Rendered cases with a
  path-traced step should either skip that step on the stock engine or be
  tagged for the patched build only.
- `GameSound.step` (`game_sound.gd:634`) is an empty stub; its last caller,
  the footstep distance bookkeeping in `GameUnit._draw_step`, was removed in
  this pass. The stub can go with the next sound change.
- `spell_callback` spikes in the Portal profile (0.24 ms per tick average,
  single calls over 5 ms in `profile_slow`): not investigated.

## 7. Zone loading (the Portal, 415 units)

The solo campaign loads a zone twice in sequence: the worker builds the
authority world, then the client builds its own after `_rpc_zone`. Measured
with temporary `GameData.trace` timers (not committed; logs in
`local/validation/cpu-speed-20261029/zone-load/`):

| phase | worker (headless) | client (2880×1800, cold caches) |
| --- | --- | --- |
| `Session._build_world` | 10.4–10.9 s | 13.3 s |
| ├ `EIMapScene.load_map` (terrain, 3171 objects) | 1.5 s, +139 MB | — |
| ├ `NavGrid.build` | 1.5 s, +215 MB | — |
| ├ `spawn_unit` × 413 | 6.2 s, +585 MB | 9.9 s (`_rpc_zone` spawn) |
| ├ `nav.layer` per standing class | 0.7 s, +470 MB | — |
| `_deploy_parties`, vm, rest | 0.25 s | 0.3 s |
| shader warm-up | — | 11.0 s |
| total after the save is read | 12.0–12.4 s | ~31–34 s after the worker |

`GameUnit.setup` per unit (worker, 413 units): `EIUnitModel.create` 6.8 ms
and the first `player.advance(0.0)` 7.6 ms, everything else 0.3 ms.

Done in this pass (second): the client's `_rpc_zone` build now starts
when the host announces the zone, not when its records arrive (lead 1
below). Measured on GPU Lab (2880×1800, Portal save, idle machine, wall
clock from the worker's "zone load" to the client's "zone ready"): 46–47 s
before this pass, 34 s with the pruned libraries, 25 s with the build ahead
(`local/validation/cpu-speed-20261029/zone-ahead/solo-load-wallclock.txt`).

Done in this pass (fourth): the client's work after the zone message was
attributed (`local/validation/cpu-speed-20261029/zone-load/portal-client-phases-after-wide.txt`,
GPU Lab, warm, 415 records, 5.1 s): spawning 2.86 s (model creation 2.42 s =
atlas composition 0.88 s, clip libraries 0.80 s, part nodes and meshes
0.67 s; first pose 0.15 s, snapshots 0.10 s), `ShaderWarmup.run` 1.66 s
(the terrain colour cache 0.86 s, the materials 0.25 s, HUD previews
0.08 s, ~0.45 s in its tail not split), `attach_world` 0.19 s, taking the
world built ahead 0.32 s. The libraries and atlases are now prepared during
the build ahead from the map's own unit records (`EIUnitModel.prewarm`);
solo Portal load on GPU Lab, warm: 13 → 11 s (the client's part after the
message 5 → 3 s; 67 libraries and 92 atlases prepared for 413 records
before the worker published). Remaining there: the part nodes and meshes
(scene-tree work, 1.6 ms per unit), the terrain colour cache preparation
(native jobs; it needs the camera's position, which `village_start_view`
sets after the spawn), and the warm-up tail.

Done in this pass (fifth): the headless authority spawns its units without
their atlases (`GameWorld.presentation` off → `EIUnitModel.create(…,
textures)` false; lead 2 below). Its Portal build 5.9 → 5.1 s by its own
uptime deltas (`local/validation/cpu-speed-20261029/authority-textures/solo-load-wallclock.txt`).
The end-to-end wall clock stays 11 s: the client's build ahead (6 s from the
worker's "zone load") and its navigation preparation (1.4 s) now end
together with the worker's publication, so the client's own path is the
critical one. The next second therefore comes from the client's build ahead
(terrain presentation build 1.8 s warm, object placement 2.2 s, navigation
build 0.7 s, preparation 1.4 s) or from the client's part after the message
(3 s), not from the worker.

Done in this pass (sixth): the wall-seam trimming (`WallSeams.apply`,
rendering triangles only) is skipped on a map loaded for a world that
presents nothing: 0.30 s of the worker's Portal build (not yet measured on
GPU Lab). Attributed next (`local/validation/cpu-speed-20261029/zone-load/run-pass8-ahead-phases.log`):
the client's part after the zone message is 3.5 s = spawn 1.28 s (model
creation 0.89 s: part nodes and meshes, since libraries and atlases are
prepared ahead), shader warm-up 1.80 s (terrain colour cache 0.86 s =
creation 0.28 s + an 8-page native bake 0.58 s on the four pool threads;
materials 0.35 s; first picture 0.39 s), world take-over 0.32 s, attach
0.19 s.

Done in this pass (seventh): the colour cache is created in the client's
build ahead (`Session._construct_world`; `TerrainColorCache.create` works
out of the tree) and, after the zone message, `_prepare_ground_ahead`
focuses the rig where the local hero's record stands
(`CameraRig.village_start_view(zone, at)`, else `focus`) and starts the
view's page bakes (`prepare_start`, pumped every 16 spawned records by
`prepare_pump`) before the replica spawn; `ShaderWarmup.run`'s
`prepare(cam)` joins them. Solo Portal load 11 → 10 s warm; the client's
part after the message 3.5 → 2.8 s
(`local/validation/cpu-speed-20261029/ground-ahead/solo-load-wallclock.txt`).
A presenting co-op host (`_build_world` + `_start_pose`, not `_rpc_zone`)
does not get the early start yet. Remaining on the client's path after the
message: model creation 0.89 s (part nodes and meshes; whole models could
be pre-built ahead per map record and adopted when the host's record's
gear plan matches), the world take-over 0.32 s, attach 0.19 s, the
materials' warm-up 0.35 s and the first picture 0.39 s. Remaining in the
build ahead: `EIUnitModel.prewarm` 1.74 s is serial per record, object
instantiation 0.67 s, the mob read 0.20 s.

Done in this pass (eighth): a map loaded for a world that presents nothing
places its objects without mesh instances (`EIFigure.instantiate(…,
meshes)` false; the part nodes, `EIFigureGeometry`, lever morph metas and
the record footprints stay). Nothing on the authority read the object
meshes except the navigation decal layer (presentation), the lever blend
shapes (presentation) and a radius fallback for objects without authored
geometry (`GameWorld` radius helper; `EITerrain.add_surface` has no
callers). Measurement in `local/validation/cpu-speed-20261029/object-meshes/`.

`prewarm` cannot simply run its record loop as a wide group (reviewed,
not changed): the loop writes seven shared caches after their heavy work
(`EIFigure._models`, `Items._cache`, `_template_paths`, `EIAnim._libraries`,
`_textures`, `_surface_textures`, `RaytraceTextureSource._owners`), reads
`GameData.figures` / `textures` through one shared `FileAccess`
(`EIResArchive._read_range` seeks then reads), calls `NetStatus.keep_alive`
(main-loop and peer polling), and a nested `Portability.group` inside
`EIAnim.library` would start 8 × 8 threads (or block pool tasks on pool
tasks where `wide_lanes` is 0). The feasible split: phase 0 on the main
thread derives the plans and deduplicates to the unique library keys (67)
and atlas keys (92) and reads their bytes; phase 1 runs a wide group over
those unique items with pure functions (`EIMmp.decode` + an
`_compose_image(images) -> Image` / `_compose_surface_image`, and a
`build_library(bytes, keys, scale)` split out of `EIAnim.library` with a
`parallel` flag on `_copied`); phase 2 on the main thread creates the
textures, calls `RaytraceTextureSource.remember` and inserts into the
caches. Most of the 1.74 s is those 67 builds and 92 compositions; the
other ~320 records are cache hits. `height_scale` reparses nothing
expensive: 413 calls take 44 ms headless (measured), so it needs no cache.

Done in this pass (third): the objects' navigation footprints are worked
out on the worker threads (`NavGrid._footprints`); `NavGrid.build` for the
Portal 1.41–1.46 → 0.67–0.70 s on both processes (lead 5 below). Solo Portal
load on GPU Lab, warm caches: 15 → 14 s wall clock (worker build 7 → 6 s),
13 s with the load-time groups on eight threads (worker build 5 s).
The worker's critical path after its build is the static navigation
preparation (1.4 s, already on the four-thread pool) before it publishes.

Done in this pass (first): the first advance was AnimationMixer resolving all
~41 000 tracks of the template's library (117 clips × ~350 part paths, of
which the figure holds ~20); `EIAnim.library(..., present)` now gives the
unit the clips without the other parts' tracks (2100 tracks). First advance
9.3 → 0.5 ms, worker load 12.0–12.4 → 8.5–9.6 s. The same rebuild happened
at run time on the stock engine after every finished non-looping clip
(11.0 → 0.3 ms per unit; the patched engine's
`set_preserve_track_caches_on_finish` avoided it already).

Remaining leads, in order of expected value:

1. Done: **client world built ahead of the zone message.** The host
   announces the zone (and map variant) at the start of `_enter_zone`
   (`_rpc_zone_ahead`); the client runs `_construct_world(z, false)` at
   once and `_rpc_zone` takes that world (`_take_ahead_world`) and only
   spawns the records. Worker and client builds overlap; mismatches,
   replacements and the session's teardown free the world built ahead.
   Not done: spawning the replicas needs the host's records, so the 415
   `spawn_unit` calls (client ~6 s after the pruned libraries) still follow
   the message; a client could pre-create models per prototype while it
   waits, if the records' gear is known (it is not, before the message).
2. Partly done: **`EIUnitModel._build` for a headless authority** (6.7 ms
   per unit: base `.anm` decode ~1.1 s total, texture/material composition
   0.85 s, part nodes 0.28 s, `template_paths` 0.18 s (now cached per
   template), meshes 0.15 s). Done: a world with `presentation` off spawns
   its units with `textures` false (`EIUnitModel.create`), so `_compose` /
   `_compose_surface` are skipped there; the detailed heads keep their
   authored face texture (cached per face, cheap). Not done: the meshes
   (0.15 s; `_eye_offset` and the welded joints read them, verify on the
   authority before skipping), the detailed heads and the per-part material
   variants (`FigureMaterial.part_material`), all presentation-only.
3. **Shader warm-up on the client (11 s cold).** `ShaderWarmup` runs after
   the client world is built; whether it can overlap the worker load or the
   replica spawning is a rendering-side question (out of this pass's scope
   where it touches the path tracer).
4. **Memory**: the worker's static memory grows 457 → 2210 MB for the Portal
   (RSS 802 → 2510 MB) while mesh arrays are 13 MB and texture images 80 MB.
   `nav.layer` adds 470 MB (one grid per standing class) and `NavGrid.build`
   215 MB; the 585 MB of unit spawning is unexplained (14 413 MeshInstance3D,
   1 130 materials, 415 AnimationPlayers, the per-height/per-part-set
   library copies ~27 MB). `OS.get_static_memory_usage` deltas per phase,
   as in the zone-load logs, are the tool.
5. Partly done: **`NavGrid.build` and `EIMapScene.load_map` on both
   processes.** Headless Portal, `local/validation/cpu-speed-20261029/nav-build/`
   (`nav_build_micro.gd`): `NavGrid.build` 1.41–1.46 s = object footprints
   1.13 s (`_footprint` → `_raster_box`, GDScript box sampling for 3261
   objects) + registering them 0.11 s + walk layer 0.08–0.12 s + native
   `base_cells`/`prepare` 0.07 s; six more standing-class layers 0.44–0.60 s
   (native `build_layer`, ~90 ms each, serial). The footprints now run on
   the worker threads (`_footprints`, one task per record): build 0.67–0.70 s.
   The pool is bounded to four threads (`project.godot`
   `worker_pool/max_threads` = 4, chosen so small per-frame jobs do not
   contend). Done next: load-time groups run on their own threads
   (`Portability.group(…, wide)`, `local/validation/cpu-speed-20261029/wide-groups/`),
   and the sweep showed GDScript jobs scale poorly: footprints 4 lanes
   330 ms, 8 lanes 260 ms, 16 lanes 215 ms, 32 lanes 640 ms; unit model
   creation (clip decoding) 6.1 → 5.6 ms per unit at 8 lanes, 8.0 ms at 32.
   The limit is eight lanes (`WIDE_LANES`). The static navigation
   preparation (7 native jobs, 1.39 s on the worker's critical path before
   it publishes) did not change with 8 lanes against the pool's 4: one
   class's job dominates, so the next gain there is inside the native
   kernel (`prepare_routes` per class), not more lanes. Where the GDScript
   contention comes from (ObjectDB and refcount traffic on shared records
   and models, allocation) was not profiled; a native footprint rasterizer
   (`_raster_box`) would remove it. Not done: the class layers
   (`nav.layer` per standing class, 0.45–0.7 s) could build in parallel if
   the native builder's `_fixed_sets` sharing per class group is made
   thread-safe; `EIMapScene._place_objects` 0.75–1.15 s headless (3261
   `EIFigure.instantiate`: node trees, cached meshes 0.4 s when cold) and
   2.2 s on the client (materials, `GroundContact`, scenery batches) is
   scene-tree work and would need the meshes built ahead on the pool.
6. **Presentation terrain build on the client** (`EITerrain.load_map(…, true)`,
   GPU Lab 2880×1800, `local/validation/cpu-speed-20261029/terrain-build/`):
   6.2–6.3 s with cold caches, 1.84 s warm. Phase sums over the sectors:

   | phase | cold | warm | note |
   | --- | --- | --- | --- |
   | `apply_gfx` → `TerrainCliff.create` | 3.01 s | 0.24 s | disk cache `terrain_cliff_cache.gd` |
   | `apply_gfx` tail after the shaders | ~2.0 s | ~0.28 s | detail atlases (`TexUpscale`), `WaterCurrent`, noise textures; not split further |
   | `apply_gfx` land / water shader | 0.02 / 0.01 s | 0.07 / 0.03 s | compilation is asynchronous |
   | `_mesh_arrays` (GDScript per-vertex loops) | 0.65 s | 0.62 s | per sector, pure: a `Portability.group` or native candidate |
   | `_read_vertices` | 0.16 s | 0.16 s | also headless (worker) |
   | water `_make_mesh` | 0.15 s | 0.15 s | `_mesh_arrays` again |
   | liquids (`_vertex_materials`, `_liquid_xy`, `_underwater`) | 0.14 s | 0.14 s | |
   | atlases | 0.06 s | 0.08 s | |
   | `configure`, `_build_surface_data`, ground | 0.15 s | 0.15 s | |

   The headless (worker) build of the same map is 0.29 s. The warm client
   build is ~1.0 s of GDScript sector loops: moving `_read_vertices`,
   `_mesh_arrays` and the liquid helpers to one task per sector (they read
   the sector bytes and the material table and write per-sector arrays; the
   shared `heights`/`land_xy`/`land_n` rows would be merged on the main
   thread) is the remaining terrain lead. The cold cliff cache and the
   `apply_gfx` tail are one-time costs per installation.

## 8. Operational notes

- A worktree of this repository needs `godot-4 --headless --path game --import`
  then `git checkout -- game/assets` before headless tests load
  (`RemakeText not declared` otherwise).
- The focused runner's 840 s case timeout includes GPU Lab queue time; with
  the lab busy, rendered negative controls must be started when a slot is
  free (`/usr/local/bin/gpu-lab status`), not queued blindly.
- GPU Lab jobs have their own `/tmp`: a probe script or save kept in a
  session scratchpad under `/tmp` is "File not found" inside the job. Keep
  probes and outputs under the project tree (`local/validation/...`,
  `local/scratchpad/...`).
