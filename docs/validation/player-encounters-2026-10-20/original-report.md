# Original-versus-remake comparison

Result: **mismatch**. 425 matching scenarios; 5 differing scenarios; 1124 original observations.

Reference: `d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8`.

These are bounded subsystem replays with declared supplied boundaries. They do not establish a complete campaign, save/load, multiplayer or graphical match.

The original capture executes the user's x86 instructions in Unicorn. The remake capture calls production game methods and receives only inputs. No mismatch is automatically approved.

| Scenario | First difference | Original | Remake |
|---|---|---|---|
| `attack_chance/a41_d40_distance1` | `$.steps[0].state.probability` | `0.4878048780487805` | `0.51219512195122` |
| `attack_chance/a41_d40_distance5` | `$.steps[0].state.probability` | `0.4878048780487805` | `0.51219512195122` |
| `attack_chance/a40_d40_distance10` | `$.steps[0].state.probability` | `0.4634146341463415` | `0.48780487804878` |
| `attack_chance/a41_d40_distance10` | `$.steps[0].state.probability` | `0.4878048780487805` | `0.51219512195122` |
| `attack_chance/a20_d10_distance10` | `$.steps[0].state.probability` | `0.5853658536585366` | `0.609756097560976` |

## Coverage contracts

### clock

Original raw timestamp loop versus GameWorld._sample_frame; simulation bodies are counters.

Supplied boundaries: OS timestamp; application active flag; server/client dispatch bodies; render dispatch.

No world simulation, input handling, rendering or worker debt retention is covered.

Tolerances: `{"remainder_ms": {"abs": 2e-05}, "draw_fraction": {"abs": 1.2e-07}}`.

### cast_rank

Original candidate-selection loop versus Spells._cast_pick, including dead-node removal.

Supplied boundaries: dead predicate; removed-list-node cleanup; candidate list and ground heights.

Does not cover target acquisition, line of sight, spell application or damage. This terrain fixture requires one ground height per XY coordinate.

Tolerances: `{}`.

### script_random

Original Random opcode with supplied uint32 words versus ScriptVM.random_value.

Supplied boundaries: one-word native RNG queue.

Tests the mapping, not the RNG generator or whole-game random draw order.

Tolerances: `{}`.

### sight_factor

Original observer sight multiplier versus GameUnit.sight_factor.

Supplied boundaries: world lookup; darkness/weather/night-sight/posture inputs.

Does not establish complete stealth, terrain occlusion or AI behavior.

Tolerances: `{}`.

### interaction_reach

Original type-6 interaction distance versus ScriptVM._interact_reach.

Supplied boundaries: figure/use radii; target type accessor.

Does not cover route planning, inventory transfer or actual lever use.

Tolerances: `{}`.

### attack

Original hit decision with zero random spread versus Combat.attack_hits.

Supplied boundaries: attack/defence record accessors; target special-case predicate (false); target use radius.

Synthetic no-spread boundary cases. Does not cover damage, armour, backstab or RNG equivalence.

Tolerances: `{}`.

### attack_chance

Enumerate all supplied native roll residues versus Combat.hit_chance.

Supplied boundaries: attack/defence record accessors; target special-case predicate (false); target use radius; one-word native RNG queue.

Compares the combat probability query for unaimed attacks. Does not test the remake RNG stream.

Tolerances: `{"probability": {"abs": 1e-12}}`.

### village_gate

Original village-talk eligibility branch versus GameUnit.village_talk_ready.

Supplied boundaries: present unit controller; current and posted command records; branch endpoints.

Tests eligibility for all command-code pairs, not command dispatch or dialogue content.

Tolerances: `{}`.

### darkness

Original simulation darkness versus GameWorld.darkness at clock boundaries.

Supplied boundaries: world hour; zero elapsed world-clock ticks.

Does not test rendered daylight, weather changes or the clock's progression.

Tolerances: `{}`.

### eye_height

Original normal-figure eye position versus GameUnit.eye_z.

Supplied boundaries: ground-height getter; dead predicate; figure half-height; posture.

Normal grounded figures only; no flying eye approximation or occlusion query.

Tolerances: `{}`.

### faction_relation

Original directional faction-bit updates versus GameWorld.set_relation.

Supplied boundaries: initial self-friend relation matrix; no unit-notification recipient.

Matrix updates only; individual hate, taming and notification side effects are separate regressions.

Tolerances: `{}`.

### path_refine

Original turn-template builder and local path-refinement pass versus NavTurn.refine.

Supplied boundaries: CRT allocation/free; supplied navigation costs, slopes and occupancy; unit move-class/threshold accessors.

Refines supplied routes; does not establish whole-route search or collision/spline equivalence. Heading is a supplied direction code.

Tolerances: `{}`.

## Reproduction

The full native capture, including exact `inputs.json`, source snapshot and
trace hashes, remains in the local directory recorded as `original.capture`
in [validation.json](validation.json). Run the native suite with
`tools/parity/run.py --game-dir BASE_GAME --godot GODOT --out NEW_DIRECTORY --repeat 2`;
add `--replay-inputs PATH_TO_CAPTURE/inputs.json` to reuse those exact inputs.
The default seed is 20261020. This directory's `reproduce.sh` runs the full
gameplay selection and the separate original comparison.
