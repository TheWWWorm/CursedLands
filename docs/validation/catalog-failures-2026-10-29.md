# Pre-existing catalog failures (2026-10-29)

The 1.37.0 release run reported 27 headless and 25 packaged Linux programs
that failed identically on 1.36.0. Each group below was reproduced, classified
as a product bug, a stale fixture or an environment limit, and fixed or
recorded. Inputs: base GOG data, **LiA 1.02** (`local/runtime/reference/lia-1.02`),
original RU/DE text archives, Godot 4.7 official headless, the published
1.37.0 Linux package for packaged reruns, GPU Lab `gpu=auto` for rendered runs.

## Environment: wrong LiA data in the 1.37.0 run

The release run passed the unpatched LiA disc tree
(`inspection/lost-in-astral/game`) as `--astral-data`. With LiA 1.02,
`story_coop_effects`, `story_coop_predicates`, `zone7_arrival` and the LiA
first-visit order shards pass without changes (the disc data yields 162 order
cases, so shards 07–10 fell below their minimum). No code change.

## Product fixes

| Group | Cause | Fix | Regression |
|---|---|---|---|
| `unit_sound_state` | `UnitSounds.tick` assigned each registry row to a typed `GameUnit` before `is_instance_valid`; Godot 4.7 rejects assigning a freed instance, so a stale row raised a script error every tick. | Check the untyped row first (game and reference implementation). | `focused/unit_sound_state` leaves a freed actor in the registry; errors before, 1137/0 after. |
| Co-op solo checkpoints (`coop_vm_solo`) | `Session.enter_zone` ran the collect/deploy transition on a session's first deployment even when the loaded owner was already the selected party. Nothing had been collected, but the host archived its live bag; a guest with an identical story then no longer matched. | A first deployment transitions only when a different party was selected beforehand (LiA chapter starts still load it). | `coop/coop_vm_solo` 1 failure before, 30/0 after; `lia_kel_rescue[_startup]` (preselected party) 146/0. |
| `vegetation_warmup` | The loading-time cover warmup built a record without the `snow`/`flower`/`cold` fields every streamed record has; `Geometry.build` failed, so the warmup mesh was empty and the variant was not prepared. | Give the warmup record the streamed shape. | Negative control: with only the test fixture corrected, the program still errors; with the fix, 124/0. |

Original comparison: the collection rule follows the LiA 1.02 evidence in
[the party inventory note](lia-party-inventory-2026-10-24.md) (collection
`0x4edac0` → storage `0x4621b0` at travel and `RedeployParty`). That a first
deployment of an unchanged owner collects nothing is an inference from that boundary; it was not
re-observed under Wine in this task. Co-op checkpoints, the sound registry and
the cover warmup are remake systems without an original counterpart.

## Stale fixtures

| Program(s) | Cause | Change |
|---|---|---|
| `worker_travel_clock` | Required `zone3.mob`; the base campaign uses `zone3obr.mob`/`.mpr`. | Correct required files. |
| `path_preview` | Order trails moved to the real-time `OrderFx` node (they draw while paused); the test inspected the gameplay `ParticleFx`. | Inspect `ParticleFx.for_order_marks`. |
| `recruited_equipment_net_astral` | LiA `merc2` is Kel, deliberately kept by the host (`Session._story_companion`, 5829e099). The guest's unequip commands were correctly refused. | LiA uses `merc10` (bz2h) and asserts the fixture is guest-assignable. |
| `coop_guest_roles_net[_astral]` | The prepared saves selected a party without deploying it, which no real save can contain; the host's first deployment then made that party its loaded owner and the guest's import did not match. | `prepared()` deploys its party. |
| `coop_solo_return` | The prepared solo save "travelled" to the camp without the native collection that travel performs (rule added 10-24). | The fixture performs that collection. |
| Six `base_campaign_gipat_*` departure/farewell programs | The authored Ingos script opens `q42k` a few ticks after arrival (`base_campaign_ingos_arrival` checks this); the reload comparison counted it as a replayed reward. | Settle and assert the arrival quest before the checkpoint; the comparison stays exact. |
| `gipat_captive_dialogue_hermit_first` | bz4g `#OnBriefingComplete` offers `Ha29_1`/`Ha29_2` on the tick after the briefing closes. Hermit-first order reached an already-ready NPC with no tick in between. | Wait up to 30 ticks for the native offer before approaching. |
| `arena_economy`, `arena_live_shop` | Looped over LiA expansion families 30–37, which exist only with a mounted LiA database. | Cover them only when `ArenaExpansion.mount()` succeeds. |
| `arena_result_health`, `arena_elimination_places` | Round damage changed on 10-27 (310edbb2): creep rounds deal none, defeats cost `wave/10 + survivors`. The fixtures fought wave 1 and expected the old fixed losses. | Fight a player round (wave 4) and derive losses from the rules. |

Arena (Autochess) is a remake mode; no original comparison applies.

## Packaged Linux

- **Live DLSS RR cases** (`path_trace_rr_details`, `_rr_live`,
  `_rr_traversal_*`, `_rr_unavailable`, `_rtxdi_live`, `_travel_rr[_night]`):
  RR and FG require a Windows Direct3D 12 runtime; Linux keeps NRD
  ([integration](../integrations/dlss-ray-reconstruction.md)). New catalog
  field `platforms: ["windows"]`: both runners report these as skipped
  elsewhere, never run or passed.
- **`path_trace_transmission_live`**: Linux runs 21 of 25 assertions; the RR
  branch is Windows-only by design. New field `platform_min_checks: {"linux": 21}`.
- **`terrain_cliff_composed_gl`**: Compatibility never creates the native
  colour cache, so its cache assertions do not run; the GL variant completes
  21 checks with 0 failures from source and packaged. Its minimum (24) had been
  copied from Forward+; it is now 21.
- **Unresolved: arena UI first click** (`arena_equipment_roster_ui_*`,
  `arena_item_first_click`, `arena_reserve_moves_ui`). These pass from source.
  With the 1.37.0 package, the first synthetic left press of the process never
  reaches the hovered button (no `button_down`); later presses work. The same
  package passes with `--render-thread safe` (10/10), so the difference is the
  separate render thread enabled by `thread_model.render_thread_patched=2`.
  Whether real X11 input from a player is affected is not established. The tests
  and engine setting are unchanged, pending a real-input check on the threaded
  build.

## Verification

See the retained run summary in
`local/validation/catalog-failures-20261029/` (private workspace).
