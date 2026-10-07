# Reactive AI activity scheduling

The player-facing contract is prompt detection and response, natural patrols, reliable scripted encounters, unchanged movement and core combat rules. Internal execution order, cache-refresh randomness and exact ambient replays are not fidelity requirements for this system.

## Implemented architecture

The authority checks for potential calm waiters after the quest VM and before the ordinary unit updates. A population with no eligible calm actors bypasses the activity pass. Otherwise it runs a shared activity pass. An adapter extracts positions, factions, current sensing bounds, party/dead/hidden flags and directional hostility masks into packed arrays. `AIActivityKernel` operates on those arrays only. Its engine-independent C++ core aggregates 32 m cells: each cell has a faction mask and flags for party members/corpses. Querying a cell does not enumerate all its occupants, so an increasingly crowded friendly cell does not introduce an all-pairs scan.

The result is deliberately conservative: a cell intersecting a sensing region can keep a unit active even if the actual target is a little farther away. It must never declare a region quiet when it contains a qualifying stimulus. A matching GDScript implementation supports platforms without the native library. No camera, renderer visibility or single-player fog setting participates in authority decisions.

A quiet result permits a cheap deadline check. A calm NPC holding a glance can wait until that glance ends; an NPC on a calm patrol leg can keep moving without re-evaluating its motivations. At the deadline, or when a relevant interaction exists, ordinary decisions resume. This replaces repeated idle motivation/perception evaluation; it does not skip the unit's simulation tick. Health/stamina, pending damage, movement, spell duration, quests, noise/help/alarm timers and chatter continue normally.

This first scheduler still receives the existing 55 ms world updates and performs a small live eligibility check per decision. It is not a fully asynchronous AI engine or a complete rewrite of combat decisions. Absolute patrol deadlines, rather than a lower fixed decision frequency, govern when quiet decisions become necessary. Existing quest, combat and movement code serves as the behavioral adapter.

## Wake-up contract

Player-controlled units, heroes, marked script actors, active non-calm orders, queued orders, failed paths, animation locks, wounds, buffs, pending hits, suspicious/fearful/alerted actors, retained noticed units/corpses, custom motivation/hostility states, friendly-spell casters and area-spell dangers bypass deferral. Different neutral factions alone do not wake each other. Hostile factions are directional, including self-faction hostility.

Health eligibility reads the body-derived `hp` property. The internal `_hp`
field is a fallback for units without body parts and does not track co-op
maximum-health scaling or ordinary body wounds. Reading that fallback disabled
quiet scheduling for healthy scaled populations; it could also miss real wounds.
The focused `tools/tests/ai_activity_health.gd` regression covers scaling,
injury, healing and removing scaling.

Membership operations and diplomacy commands invalidate the current batch immediately. Changes to dead/hidden/controller/faction fields use the existing notice revision. Positional writes compare against the tick snapshot; displacement exceeding 1 m invalidates the remainder of the batch. The sensing envelope includes 2 m of movement margin, shared between observer and target. The former 16 m envelope kept many distant actors active unnecessarily. The smaller envelope uses the same immediate overflow fallback, including fast moves and teleports; it does not impose a movement limit. Dialogue, clients and nonstandard diagnostic timesteps use ordinary decisions. Queries outside the unit-update phase also use ordinary decisions.

Sleeping invalidates the old neighbour-refresh deadline. Waking therefore queries current neighbours instead of waiting as long as the previous 8–11-tick cache interval. Movement and patrol timing are not slowed because a unit is far from the player. The earlier `Distant AI (experimental)` setting is a separate approximation experiment and remains off by default.

The scheduler is enabled by default. `-- --ei-legacy-ai` disables it for comparison. `-- --ei-script-activity` exercises its script implementation. These are diagnostic switches; there is no additional gameplay quality setting. Derived activity data is rebuilt, never written into saves or sent over the network. The server schedules all co-op participants using the same world snapshot.

## Data, threading and compatibility

The native core has no scene objects, Godot property calls, shared mutable caches, RNG calls or world mutations. Its input/output boundary is suitable for future independent worker jobs. The current pass is synchronous: thread dispatch is not justified solely by the existence of a pure function, and the cost of extracting data from GDScript must be counted too. Count extraction and adapter costs when benchmarking; kernel timings alone do not measure gameplay performance.

Original map assets and quest scripts remain content inputs. Original per-unit cache-refresh cadence is not the scheduling model. Skipping otherwise-empty perception refreshes changes global RNG consumption, so whole-world ambient trajectories can differ even though the combat formulas and combat RNG implementation are unchanged. Exact legacy replay equivalence is expected only with the diagnostic off switch. Enabled repeats should remain deterministic for equal inputs.

## Validation and next boundaries

`tools/ai_activity_test.gd` compares the native and script batches, checks a separate point-distance safety oracle, invalid/malformed inputs and wake-up triggers. `tools/reactive_gameplay_test.gd` exercises real registered units in River and Islands, including patrol deadlines/movement, stealth, teleport invalidation and first-tick wake-up. Existing AI, save and quest checks cover the adapter boundaries. Passing these fixtures is not a complete campaign playthrough.

Crowded navigation is the next priority: repeated reachability checks and route retries can dominate active combat. The goal is to make the default systems efficient enough that the optional distant-AI approximation is unnecessary. Other architectural boundaries are active-combat perception and animation application. Perception can publish typed observations to a decision service; decisions can produce intents; movement/combat can commit those intents in the authority phase. Authoritative damage, path completion, command, diplomacy and quest events should drive invalidation. Per-system or per-actor random streams would make ambient scheduling independent of other decisions, but require an explicit save/replay migration. Batch animation work separately because it is another major CPU cost and this scheduler cannot remove it.

Each further migration should be accepted by whole-frame measurements, bounded reaction latency, patrol/stealth/combat scenarios, save/load and co-op tests. A smaller helper benchmark alone does not establish a gameplay improvement.
