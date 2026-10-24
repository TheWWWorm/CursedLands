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

Sleeping invalidates the old neighbour-refresh deadline. Waking therefore queries current neighbours instead of waiting as long as the previous 8–11-tick cache interval. This scheduler does not slow movement or patrol timing because a unit is far from the player; the original's own active-object set does, see below. The earlier `Distant AI (experimental)` setting is a separate approximation experiment and remains off by default.

The scheduler is enabled by default. `-- --ei-legacy-ai` disables it for comparison. `-- --ei-script-activity` exercises its script implementation. These are diagnostic switches; there is no additional gameplay quality setting. Derived activity data is rebuilt, never written into saves or sent over the network. The server schedules all co-op participants using the same world snapshot.

## The original's active objects

In zones of type `game` (map.txt; not `brief`, `edge` or the arena) the original server updates only the objects in its active set, and `ObjectActivity` (`game/src/game/object_activity.gd`) reproduces it on the authority. Every server tick, before the objects update, each unit of every player wakes all objects in the 32 m cells around it: the cells at offset (dx, dy), at most 10 cells either way, with sqrt(max(|dx|-1, 0)² + max(|dy|-1, 0)²) < r / 32, where r = 2 × max(sight × sight factor, life sense) + 20. Waking sets a counter of 128–143 ticks (about 7–8 s). A unit whose counter runs out stays awake while it is in its attack stance, its MOB logic is always-active, or it has noticed a living enemy; otherwise it is frozen until it is woken again. A woken magic trap stays awake. A magic trap selects living units in its areas using the enemy mask computed from its owner's map-diplomacy row at load (`481660`), then casts and restarts its countdown. The original unit selection (`52a920`) rejects dead units, not all units. In gz3g the resulting mask is 1, so the shrine hits the party and spares its allied creatures. See [the original-code and Wine comparison](validation/issues-109-112-2026-10-24/README.md).

An attacked unit wakes, so a long shot reaches a frozen unit. Every tick of fireworks and clairvoyance wakes the objects within the spell's radius + 5 m of its point.

A zone's units start frozen unless always-active; levers, which the original also arms at load, always update in the remake. Units created during play start awake. A saved zone (a loaded game or a revisited zone) also starts with its magic traps awake. Frozen units do not move, decide, chatter, make step noise or regenerate, so a patrol far from the party waits at its post as in the original. Party units, corpses and conversation actors always update. The set is not saved; loading re-arms it as the original does.

A revisited zone first catches up on the party's absence, before the party is placed: 100 object steps per campaign hour since it was left (at most 1000, about 55 s of play), each waking the objects within 70 m of the centre of the entrance's deploy area. No scripts run and the campaign clock stands still meanwhile. Loading a saved game does not run it.

`tools/tests/object_activity.gd` covers the freeze, the wakes, the expiry and runtime spawns in gz3g, where the original keeps goblin 3379 at its spawn while the party stays at the entrance. `tools/tests/object_activity_absence.gd` covers the absence simulation.

## Data, threading and compatibility

The native core has no scene objects, Godot property calls, shared mutable caches, RNG calls or world mutations. Its input/output boundary is suitable for future independent worker jobs. The current pass is synchronous: thread dispatch is not justified solely by the existence of a pure function, and the cost of extracting data from GDScript must be counted too. Count extraction and adapter costs when benchmarking; kernel timings alone do not measure gameplay performance.

Original map assets and quest scripts remain content inputs. Original per-unit cache-refresh cadence is not the scheduling model. Skipping otherwise-empty perception refreshes changes global RNG consumption, so whole-world ambient trajectories can differ even though the combat formulas and combat RNG implementation are unchanged. Exact legacy replay equivalence is expected only with the diagnostic off switch. Enabled repeats should remain deterministic for equal inputs.

## Validation and next boundaries

`tools/ai_activity_test.gd` compares the native and script batches, checks a separate point-distance safety oracle, invalid/malformed inputs and wake-up triggers. `tools/reactive_gameplay_test.gd` exercises real registered units in River and Islands, including patrol deadlines/movement, stealth, teleport invalidation and first-tick wake-up. Existing AI, save and quest checks cover the adapter boundaries. Passing these fixtures is not a complete campaign playthrough.

Crowded navigation is the next priority: repeated reachability checks and route retries can dominate active combat. The goal is to make the default systems efficient enough that the optional distant-AI approximation is unnecessary. Other architectural boundaries are active-combat perception and animation application. Perception can publish typed observations to a decision service; decisions can produce intents; movement/combat can commit those intents in the authority phase. Authoritative damage, path completion, command, diplomacy and quest events should drive invalidation. Per-system or per-actor random streams would make ambient scheduling independent of other decisions, but require an explicit save/replay migration. Batch animation work separately because it is another major CPU cost and this scheduler cannot remove it.

Each further migration should be accepted by whole-frame measurements, bounded reaction latency, patrol/stealth/combat scenarios, save/load and co-op tests. A smaller helper benchmark alone does not establish a gameplay improvement.
