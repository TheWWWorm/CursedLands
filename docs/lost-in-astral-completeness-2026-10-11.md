# Lost in Astral: playability, co-op, saves and testing tools

Follow-up: [deeper save-state findings, reflection investigation and the separate health-bar change](lost-in-astral-save-depth-2026-10-11.md). The baseline statements below describe the initial audit snapshot.

Investigation date: 11 October 2026. **The current engine has substantial Lost in Astral support, but complete campaign playability and complete save-state coverage are not established.** This audit reproduces a late-join trap omission and several save/load state losses. It does not demonstrate an unavoidable main-story softlock or establish that the campaign can be finished on every supported platform.

The most useful next work is to fix the confirmed persistence gaps, extend the missing co-op trap registration, and add checkpoint-oriented testing tools to the existing Sandbox menu. No production code, original assets or player saves were changed by this investigation.

## Baseline and evidence

The current checkout is `/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo`, HEAD `dfe6dda4356cdb3af7ec749200437e2bb367ed78`. Its `game/` contents match runtime source `a9e597c91845aeada89aeb4c6a2bb2808fbd5e77`. Fresh tests used the packaged **1.0.4 Experimental 2 Linux build**, protocol 14, with the original extracted game data. Older `remake/` and `publish/` copies are not the runtime baseline.

The [machine-readable receipt](validation/lia-completeness-2026-10-11.json) records executable/package hashes, original executable hashes, fixture hashes, commands, results and local evidence paths. Test profiles had isolated data/config/cache directories. Tests used the real exported engine and full Session disk save/load; states and script boundaries were prepared explicitly. They were not complete played routes.

Ghidra was used in **read-only** mode on the existing Lost in Astral project. Relevant fresh exports include the map-object writer `0x499a50`, unit writer `0x4b0f90`, unit reader `0x4b0670`, unit-logic writer `0x4c3900`, stats writer `0x4a7410`, and AI writer `0x518b40`. Disassembly verifies stream writes where inferred decompiler types obscure arguments. The original application itself was not played for this audit.

## Original content and missing functionality

The fresh original-data census parsed **130 map scripts, 2,642 script definitions and 40,915 call sites**, with **zero parser errors**. All 112 used built-in names have dispatcher entries. This establishes name coverage, not native behavioral equivalence for every implementation.

Only five unresolved procedure names remain: `BuyHaburuMain#2#1#0` through `BuyHaburuMain#2#5#0`, called by `bz23k.mob`. They are absent from the original authored procedure definitions; the earlier independent native command-table audit also found no corresponding built-ins. Their intended optional-quest/shop behavior is unresolved. They should not be filled in by inventing rewards or progression rules.

This is distinct from Haburu's first-conversation approach defect, which is already repaired in current source. The [Haburu investigation](validation/lia-haburu-2026-10-09.json) records 379 bounded source/runtime checks, including the original first conversation and save/load. The five absent procedures did not prevent that tested conversation from completing.

The 121 map records contain six unresolved asset references:

| Map record | Missing reference | Evidence and implication |
| --- | --- | --- |
| `mov1` | `1mov.mob` | No literal travel reference found by this census. |
| `cz3h` | `cz3h.mob` | No literal travel reference found. |
| `cz4h` | `cz4h.mob` | Referenced by `zone2`'s `VCheck#6#2`; its parent gate requires `q.gz2h.q24h` to equal both 1 and 0. That unmodified gate cannot activate. |
| `gz17g` | `zone17.mob`, `zone17.mpr` | No literal travel reference found. |
| `bz15g` | `bz15g.mob` | No literal travel reference found. |

These references belong to the supplied original data. No active mandatory route into them was established. A literal-reference scan is not an exhaustive reachability proof, so classify them as unresolved/dormant content, not six proven missing playable areas.

Older audits listed many real defects that current source has since addressed: expansion map aliases, chapter rosters and purses, guest protagonist selection, death predicates, temporary roles, camp grants, guest continuation, Catacombs travel/lift behavior and the first Haburu conversation. The old lists must not be reused as a current missing-feature checklist. This audit reran the packaged `campaign_roster.gd` fixture: **64 checks passed**, covering prepared ownership/death permutations, named chapter imports, temporary roles and idempotent grants.

Remaining fidelity differences in combat, effects, rendering or exact random sequences should be tracked separately from campaign blockers. A supported script name alone is insufficient evidence that its timing, persistence and multiplayer consequences are all correct.

## Co-op: one newly reproduced omission and remaining acceptance

Lost in Astral's original campaign supplies no multiplayer campaign specification. The remake must preserve the authored story roles while adapting participant-specific hazards and progression for additional players.

### C01 — late arrivals bypass both `gz13g` lethal traps

The original `zone13` roots `Trap#0#1` and `Trap#1#1` kill their own registration thread, iterate the current `Heroes`, and spawn one child watcher for each present actor. A player arriving after this iteration gets no watcher. Current [co-op trap adaptation](../game/src/game/script/story_coop_traps.gd) handles other families, but does not handle these roots.

The diagnostic used the real `gz13g` map and its exact area statements and trap bodies:

1. A host present at activation enters each trap and dies; the host is then revived outside it.
2. After the initial registrations finish, a guest joins over real loopback ENet.
3. The guest enters both trap rectangles while the corresponding quest stages remain unfinished and survives. The client receives the same result.
4. Positive control: registering the original child watcher for that same guest kills it, and the client receives the death.

All **15 diagnostic assertions** matched that behavior. The test uses two ENet peers in one process, prepared positions and paused unrelated simulation. Three runs reproduced the result, but all logged a shutdown leak warning (four ObjectDB instances and one resource). Treat this as reproducible behavioral evidence with a teardown limitation, not a clean multiplayer acceptance run.

Recommended correction: add a source-guarded registration adapter using stable participant identities, saved activation/consumption state, and the original child conditions and damage. Follow the existing trap infrastructure; do not rerun the whole WorldScript whenever someone joins. Test guest arrival, reconnect, save/load, revival, quest completion and deliberate reactivation, preserving the intended one-shot behavior for an already affected participant.

The census found eight `For(..., Heroes)` loops. The two `zone13` loops above are persistent-hazard registrations. The `zone11dun1` water registration re-arms periodically; the remaining loops are teleport actions in `cz3j`, `zone35` and `zonefinal`. Those should not all receive the same generic late-join patch.

### Coverage still required before claiming complete co-op playability

Current code and prior receipts cover important prepared transitions, including FPrison/FSusel/Gipat, temporary Shaina, recipient-specific VM state, absent participants and returning to solo. The [co-op-to-solo VM receipt](validation/coop-vm-return-2026-10-09.json) and [solo/co-op return receipt](validation/coop-solo-return-2026-10-09.json) explicitly bound their claims. A fresh roster regression does not replace those route tests.

The remaining acceptance should cover:

| Scenario | What must be demonstrated |
| --- | --- |
| Later Jigran chapters through the finale | Authored progression, party changes, endings, required inventory and travel work for the host and guests. |
| Guest finishes a chapter, leaves, then continues alone | Load the actual returned save in an independent process and complete its next objective; verify active and waiting parties, private bag/purse, quest flags and pending script waits. |
| Late join and reconnect at every long-lived hazard/escort/captivity boundary | New participants gain required watchers; old participants retain consumed effects; shared rewards and story companions are not duplicated. |
| Three extra guests at lifts, narrow exits and scripted teleports | Physical traversal and travel complete with all participants, including an idle or delayed guest. |
| Sustained actual combat and travel over separate machines | Test normal and accelerated speed, disconnect/recovery and the relevant Windows/WAN route. |

The earlier [hardware delivery receipt](validation/sustained-coop-hardware-2026-10-09.json) retained failures at 2× speed and explicitly excluded Windows/WAN and sustained combat. It is historical evidence, not a fresh test of this package. No current network playability guarantee follows from it or from the short local trap diagnostic.

## Saves versus the originals

**The saves do not yet cover all relevant live states.** Native saves serialize map objects, unit logic, a raw `0x704`-byte stats block, posture/gait, personal hostility and substantially more AI execution state. For example, the LiA unit writer explicitly streams the hostility mask at unit `+0x244` and posture/gait at `+0x264`/`+0x268`; the logic writer calls the raw stats writer at `0x4c3a9f`. The corresponding base-game writer is `0x5321c0`.

This is a comparison of gameplay-state semantics, not a claim of binary compatibility with original `.sav` files. Full save/load and leaving/re-entering a zone also have different original semantics; fixes should not assume the two operations are interchangeable.

### Confirmed state losses

| ID | State and observed result | Cause / practical effect |
| --- | --- | --- |
| S01 | Authored frozen clock: `true → false`. In actual `cz1h`, the original `VTriger#0#1` froze time at `0.3`; after loading, a 0.25-second VM tick advanced it to `0.3050505`. | `ScriptVM.save_state()` omits `time_fixed`. Restored threads resume after `FixWorldTime`, so the call is not replayed. Eight authored calls across seven LiA script files make this relevant beyond one scene. |
| S02 | Ordinary NPC mana: `2.07 / 9 → 9 / 9` in the LiA probe. Also reproduced with base-game assets. | `CampaignState.body_state()` saves NPC mana only for actors with an `npc_character` override. Ordinary creatures regain mana on load. |
| S03 | A personally hostile NPC with neutral faction diplomacy becomes neutral again after loading. | Per-unit `hate` is omitted. It also contains a runtime world ID, so restoration must rebuild it for the new world rather than copy the old ID. This can reset combat behavior. |
| S04 | A pending scripted `Attack` queue disappears and its AI state changes from `3 → 0`. | The production builtin issues a non-story-tagged order; the save path keeps selected scripted moves/rotations/clips, not this attack state. There are 60 authored Attack call sites. The probe called the production builtin directly; it did not reproduce a complete organic combat scene or a resulting story stall. |
| S05 | Hero facing: `0.987654 → 2.35619449` in LiA; also lost with base-game assets. | Party positions save HP, mana, position and gait but not facing. Deployment restores the entrance angle. NPC facing is already saved and passed the control check. |
| S06 | One targeted arrow plus one free-aim arrow becomes one arrow after loading. | `Spells.save_lasting()` requires a valid target; a directional `Projectile.launch_direct()` has none. The targeted arrow survives. This is an omission in a remake feature, not missing original functionality. |

Other observed differences need separate treatment:

- **Ordinary NPC gait resets** (`0 → 2`) when prepared without `script_ai`. Native saves retain it. Actual script `Lie`/`Crawl`/`Run` calls mark NPCs for the separate `script_ai` save path, so this is not evidence that every authored posture is lost.
- **Manual movement queues stop** on load. Source explicitly documents this choice. It is a fidelity limitation worth deciding deliberately, rather than an undiscovered parser defect.
- The internal **`order_failed` flag resets**. Its downstream persistence requirements need a focused interaction test. The first fixture incorrectly called it “IsActionFailed”; there is no such builtin. The follow-up fixture corrects the label, and no authored-predicate defect is claimed from that observation.
- `Cast` and `Follow` have related transient-order paths worth testing. Their failure was not separately reproduced here. Exact attack/cast progress, cooldowns, AI memory and random-generator continuation also remain outside a complete native parity proof.

The initial full-save probes each produced seven state mismatches in LiA and the base game. The stronger LiA probe had nine failed preservation assertions across eighteen checks, including two assertions for the same hostility loss. The clock probe had two failed preservation assertions across six checks. All completed without engine errors or warnings. These `FAIL` results are evidence of defects, not accepted product tests; raw results and before/after values are in the receipt.

### What the current save implementation already covers

Inspection of [CampaignState](../game/src/game/campaign_state.gd), [ScriptVM](../game/src/game/script/vm.gd), [Spells](../game/src/game/spells.gd) and the co-op persistence modules shows substantial coverage:

| State group | Current coverage |
| --- | --- |
| Campaign identity and progression | Campaign/profile/mod configuration, quest variables and metadata, journal objectives, visited/current zones, shops, money and inventories. |
| Party structure | Active and waiting parties, named protagonists, companions, private party bags, pets and co-op bookkeeping. Prepared roster/import checks passed in this package. |
| Unit condition | Hero HP/mana/gait and body wounds passed the fresh round trip. Per-part damage, death/corpse state, buffs and effect counters have explicit serialization paths. |
| Mutable world | NPC locations/facing/faction/hidden state, carried and looted items, tombstones, added/removed actors, levers and mover progress, diplomacy, water, trap state and corpse pools. |
| Script execution | Globals, active frames and loop progress, remaining sleeps, conditions and stable actor references, areas, alarms, objectives, briefing queue and selected scripted AI/orders. S01/S04 show that this still has gaps. |
| Lasting effects | Ground spells, delayed spell effects, homing missiles, targeted arrows, tornadoes and presentation replay records have save paths. S06 is a specific missing projectile variant. |

Except for the identified fresh controls and regression, this table describes implemented paths, not exhaustive retesting of every field or combinations of them.

### Save repair order

1. Preserve clock freeze, ordinary NPC mana, per-unit hostility and party facing. Use optional fields and explicit defaults for old saves; information never written by an older build cannot be reconstructed exactly.
2. Preserve script-issued attacks/casts/follows with stable actor references and phase information where needed. Keep this separate from the deliberate policy for manual orders.
3. Save directional projectiles with direction, remaining range/lifetime, source identity and strike data; restore without requiring a target.
4. Audit remaining live actor flags, AI execution and action timers against native stream routines. Add meaningful save-at-boundary regressions rather than only checking that fields appear in a dictionary.
5. Exercise each fix in a normal load, zone revisit where applicable, co-op host reload, guest reconnect and independently resumed guest save. Reference rebinding and co-op VM projection are part of the persistence contract.

## Debug menu proposal

### Extend the existing Sandbox

Experimental 2 already exposes **Mods and rules → Sandbox** for sandbox profiles: invulnerable party, unlimited party mana, heal living party and give 1,000 gold. Profiles keep sandbox saves/characters separate, and an ordinary save can be copied into a profile for testing. Actions already run through the authority, including the separate local simulation process. See the [current mod guide](mods.md).

There is no general map teleport or character editor in that panel. `--debug` only exposes the map-viewer link; the asset viewer does not construct a valid campaign checkpoint.

Extend [ModPanel](../game/src/ui/mod_panel.gd), [Session.sandbox_action](../game/src/game/session.gd) and [LocalHost](../game/src/game/local_host.gd), with a typed action dispatcher accepting structured parameters. Host-only execution and profile separation already exist; a new unrelated cheat system would duplicate them.

### Useful first release

| Page | Proposed controls | Correct behavior |
| --- | --- | --- |
| Travel | Search maps by localized name/ID/allod, show map type and available entrances, travel party, teleport selected actor to coordinates/cursor. | Use real campaign metadata and existing loading/peer synchronization. Validate assets and walkable placement; refresh navigation/presentation. Show that ordinary travel retains current story flags. |
| Checkpoints | Load named prepared states such as camp escape, Catacombs exit, FPrison, temporary Shaina, each Jigran chapter and finale approach. | Checkpoints include roster, flags, inventory, VM and zone state. Merely moving to the final map is not equivalent to reaching the finale. Keep checkpoint saves in the sandbox profile. |
| Characters | Select active/waiting hero or companion; edit STR/DEX/INT, XP, skills, abilities, HP/mana, body condition; heal/revive. | Identify characters by stable identity and owner. Update both live stats and persistent records, recompute derived stats, synchronize guests, and preserve waiting roles. |
| Inventory | Search actual campaign item prototypes, give/remove a quantity, edit money, inspect quest items. | Use existing item parsing and inventory transactions. Distinguish personal bag, party bag and quest ownership. |
| Story | Inspect variables, objective stages, current party, active VM waits and unknown-call counters; explicitly edit a selected value. | Show before/after values and create a recoverable sandbox snapshot. Quest stages often need several dependent changes, so prefer curated checkpoints over a universal “complete quest” button. |
| Diagnostics | Coordinates, selected object ID/prototype/owner, navigation and perception overlays, loading state, host/client lag, freeze/single-step and speed controls. | Use authoritative simulation stepping and existing pause/clock rules. Read-only diagnostics can be available more broadly than state-changing actions. |
| Reproduction | Save checkpoint, record action history, export build/campaign/profile IDs, script warnings and a diagnostic bundle. | Make a test result reproducible without editing source. Keep copyrighted original assets out of export bundles. |

Commands should validate types, finite numeric values and ranges, campaign/actor identity and the current world generation. A request queued for a previous map must not edit a new actor that reused its UID. The local frontend should dispatch to the worker; co-op guests should receive results and synchronized state rather than apply their own edits.

Build the first slice in this order: **map/entrance travel and local teleport → stat editor/heal/revive → item browser → checkpoint library and story inspector → stepping/diagnostic export**. The checkpoint library is especially valuable for proving the later co-op chapters and save boundaries above.

Acceptance should demonstrate travel with a real guest and with the separate local worker, editing active and dormant characters through save/reload, sandbox isolation during co-op return, stale-request rejection during travel, and mouse/controller/touch usability. Debug actions must remain unavailable while a load or movie owns the session. No debug-menu implementation or UI acceptance is claimed by this investigation.

## Recommended next milestone

Deliver S01–S06 persistence repairs and C01 trap registration together with focused regressions, then use the Sandbox travel/stat/checkpoint tools to qualify later chapters and guest solo continuation. A full campaign completion claim needs actual route evidence through the finale in addition to the prepared state tests. The report and receipt separate confirmed defects, original-data ambiguities, deliberate simplifications and untested scenarios so that work can be prioritized without reopening already fixed issues.
