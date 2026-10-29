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

1. Early out in `UnitAI.player_perceive` (`ai.gd:690-770`) when the drop
   pass kept nothing to recheck and `_notice_candidates` returned an empty
   list: skip `notice_candidates` and `new_visible` (both are identity on an
   empty list). Semantics unchanged; ~10 µs × 58 ≈ 0.6 ms per Foothills tick
   (~7%). Cover with the perception parity harness (`--ei-script-perception`
   switches the native kernel off; the parity tests under
   `tools/tests/*perception*` record each evaluation).
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

## 4. Client-side frame cost not yet measured

The player feels the client process (presentation + rendering) rather than
the worker. No per-class frame profile of the client exists for Portal
(415 units) or Foothills. Plan: a rendered GPU Lab run of the real
client + worker (`Session.local_host.start`, as `tools/tests/speed_scaling_matrix.gd`
does), sampling `Performance.TIME_PROCESS`/`TIME_PHYSICS_PROCESS` per frame
with the same `off:<Class>` subtraction variants, at 1280×800 and 2560×1440.
Candidates known from the code: `GameUnit._process` → `_present_frame` for
on-screen replicas, `EIUnitModel` animation, `NetSmooth` placement
(`world.gd:804`, native batch per frame), `UnitWounds`, and the camera/UI
scripts. The replica sleeping framework already covers off-screen actors.

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

## 7. Operational notes

- A worktree of this repository needs `godot-4 --headless --path game --import`
  then `git checkout -- game/assets` before headless tests load
  (`RemakeText not declared` otherwise).
- The focused runner's 840 s case timeout includes GPU Lab queue time; with
  the lab busy, rendered negative controls must be started when a slot is
  free (`/usr/local/bin/gpu-lab status`), not queued blindly.
