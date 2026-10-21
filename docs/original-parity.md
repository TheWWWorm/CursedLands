# Original-engine comparison suite

`tools/parity/run.py` executes the original game's x86 instructions and the
remake's production methods in separate processes, supplies the same authored
inputs, and compares their observations. It reports the first differing step
and field for each scenario. This makes small ordering, rounding and boundary
differences reproducible.

This suite covers **bounded subsystems**. It does not replay a whole
Windows game session or establish campaign equivalence.
The companion [gameplay regression suite](gameplay-testing.md) exercises quest
scripts, creatures, animation, effects, stealth, commands and pathing.

## Run it

Requirements: Python 3.11 or newer, Godot 4.7, the pinned Unicorn emulator, and
an owned original game installation. Capture is enabled only on Linux. Its
profile isolation uses XDG directories; other host platforms need a qualified
profile-isolation adapter before capture can be enabled.

From the repository root:

```sh
python3 -m venv .venv-parity
.venv-parity/bin/python -m pip install -r tools/parity/requirements.txt
.venv-parity/bin/python tools/parity/run.py \
  --game-dir /absolute/path/to/original/game \
  --godot /absolute/path/to/godot \
  --out /absolute/path/to/new-results
```

The original directory must contain `game.exe` and the original game data.
The default qualified reference is the GOG English base-game executable with SHA-256:

```text
d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8
```

Lost in Astral has a separately inspected adapter and executable identity:

```text
f04a305b77c84ea29c18ad2996d23072ccef1c0c46876c9b93bae4ce9351d1ff
```

Use `--campaign lost_in_astral` with its installation directory. The runner
rejects unqualified executable hashes and cross-campaign contracts **before
executing any native address**. Astral currently qualifies quest predicates,
quest condition gates, persistent command bodies and Random; it does not inherit the base game's combat,
body, effects, clock or path addresses. Neither reference includes extra patches.

The default base suite has **1,757 scenarios in 18 families**; the Astral suite
has **815 scenarios in four families**. `--authored-quests` adds up to 120
supported condition lists from that installation's original MOB files.
The default seed is `20261020`. Each side runs twice in
fresh captures; differing repeat captures are an error, even if one pair
matches. The run creates a private source snapshot and fresh profiles with the
cursor free, FPS enabled and all three audio volumes muted. It never reads or
copies a player's settings.

```sh
# List inputs without Godot, Unicorn or game data.
python3 tools/parity/run.py --list

# Add real base-campaign condition lists with supplied actors and flags.
.venv-parity/bin/python tools/parity/run.py \
  --game-dir /path/to/original --out /tmp/parity-quests \
  --authored-quests

# Independently compare Lost in Astral with its own original executable.
.venv-parity/bin/python tools/parity/run.py \
  --campaign lost_in_astral --game-dir /path/to/astral \
  --out /tmp/parity-astral --authored-quests

# Include every condition list supported by the native adapter.
# Unsupported lists are still recorded as gaps.
.venv-parity/bin/python tools/parity/run.py \
  --campaign lost_in_astral --game-dir /path/to/astral \
  --out /tmp/parity-astral-all --authored-quests --quest-limit 0

# Focus on one family; choose a new output directory.
.venv-parity/bin/python tools/parity/run.py \
  --game-dir /path/to/original --out /tmp/parity-clock \
  --case clock/ --fuzz 30

# Replay the exact captured inputs against the current source.
/path/to/new-results/reproduce.sh /tmp/parity-repeat

# Narrow that replay to one failing scenario.
/path/to/new-results/reproduce.sh /tmp/parity-one \
  --case attack_chance/a41_d40_distance1

# Test the harness without original assets or emulator dependencies.
python3 -m unittest discover -s tools/parity -p 'test_*.py' -v
```

`--game-source /path/to/checkout/game` tests another checkout. The runner retains
the exact copied files and their hashes, and the source Git revision/status when
available. `--replay-inputs` bypasses input generation, so it also survives
changes to the seeded generator. `--repeat 1` is available for diagnosis but
does not verify repeatability.

## What is compared

| Family | Observations and cases | Limits |
|---|---|---|
| Frame timing | Per-frame tick count, accumulated ticks, remainder, interpolation fraction and consumed timestamp; slow frames, inactive/resume, tick edges, clock wrap and backward time | Simulation and render dispatch bodies are counters; no world simulation or worker debt retention |
| Spell target ordering | Selected unit and remaining candidate order after each selection; elevation, equal distances, explicit/dead targets, empty lists and large distances | Supplied candidates and ground heights; no acquisition, visibility, spell effects or damage |
| Script `Random` | Exact float32 result bits for supplied unsigned RNG words and maxima | Mapping only; no RNG generation or draw-order equivalence |
| Sight multiplier | Exact float32 bits across darkness, weather, night-sight and posture inputs | No complete detection, occlusion or AI replay |
| Noticed target retention | 256 combinations of party/NPC, hostility, combat target, sight/life detectability and distance | Already noticed living targets; supplied senses and hostility, no initial acquisition, corpse handling or whole combat replay |
| Interaction reach | Exact float32 bits for loot, steal and lever distances with supplied radii | No route planning, inventory transfer or lever state change |
| Attack decision | Boolean hit decisions at zero-spread and aimed-attack boundaries | Synthetic attributes; no damage, armour, backstab or RNG equivalence |
| Hit probability | Original hit decisions enumerated over every supplied roll residue, weighted uniformly, versus the remake probability query | Unaimed attacks with supplied attributes; no whole combat or RNG stream replay |
| Village dialogue gate | All 144 pairs of current/posted command codes from 0 through 11 | Present controller and supplied records; no command dispatch or dialogue content |
| Darkness | Exact float32 bits at dawn/dusk, midnight and clock-wrap boundaries | Supplied hour with zero elapsed clock ticks; no rendered lighting |
| Eye height | Exact float32 bits across normal figure heights, postures, dead/alive and ground heights | Ground/dead getters supplied; no flying figures or occlusion query |
| Faction relation | Friend/enemy masks after each update, including side 31, reversed pairs and self-relations | No individual hate or notification side effects |
| Path refinement | Refined cells and cost across 64 direction pairs plus seeded terrain/occupancy routes | Supplied routes and heading codes; flat height/slope fixtures, no whole-route search or splines |
| Quest predicates | Exact result bits and truth values for comparisons, nested arithmetic, actor distances, HP/death/identity, flags, levers, group membership/size, Any/Every, rectangle/circle areas, world time, money, quest items, loot/block flags and object height | Supplied actors/groups, player zero and absent players, single-player mode and ASCII strings; native bag traversal, group iteration, string comparison, hash lookup, area construction and containment execute normally; owned-unit inventory is empty and terrain heights are supplied |
| Quest trigger gates | Ordered condition evaluations, short-circuiting, body-dispatch events and cumulative dispatch counts across supplied states; empty/live/dead groups, iterator reuse and area entry/exit | Executes native condition-list dispatcher against `ScriptVM._run`; records body dispatch rather than replaying quest rewards or entire bodies; no sleep/one-shot lifecycle |
| Quest command bodies | Per-tick global float32 bits, observed expressions, completion and kill status; ordered assignments, zero/fractional/chained/dynamic `Sleep`, immediate/delayed `SleepUntil`, and commands after `KillScript` | One already-started persistent body; no thread-list scheduler, spawning, reward delivery or original save serialization |
| Body health | Aggregate HP and all six part states/current/max HP before and after healing or rescaling; absent, severed, disabled and active parts, tiny/negative heals, varied sizes/lethalities and repeated mixed operations | Base executable only; supplied records, no armour absorption, death dispatch, regeneration schedule or visuals |
| Effect lifetime | Signed counter boundaries, wrap, expiry and retained membership over successive authoritative ticks, on live and dead actors | Base executable only; one feeblemind lifetime, no effect application/stacking/client presentation |

The machine-readable contracts in `tools/parity/cases*.py` list native addresses,
supplied boundaries and numerical tolerances. Timing permits only its declared
small conversion tolerances. Hit probability permits `1e-12` for JSON float
serialization. Integer values, identities, booleans, order and captured float32
bits compare exactly. There is no global epsilon or mismatch allowlist.

The original adapters execute instructions from the user's executable in
Unicorn 2.1.4. The emulated x87 control word is explicitly `0x027f`; this is part
of the fixture, not a claim to have validated every original runtime FPU mode.
The loader also supplies an empty Windows SEH chain and does not handle native
exceptions. Hooks and fixture getters supply the declared external boundaries.
No original executable code bytes or assets are distributed with the suite.

The remake adapter calls `GameWorld._sample_frame`, `Spells._cast_pick`,
`ScriptVM.random_value`, `GameUnit.sight_factor`, `ScriptVM._interact_reach`,
`Combat.attack_hits`, `Combat.hit_chance`, `GameUnit.village_talk_ready`,
`GameWorld.darkness`, `GameUnit.eye_z`, `GameWorld.set_relation` and
`NavTurn.refine`, `ScriptVM._eval`, `ScriptVM._run`, `GameUnit.heal`,
body HP getters/setters and `GameUnit._tick_effects`. It receives input fixtures only;
the original observations and comparator are not staged into its project.

### Authored campaign conditions

`--authored-quests` reads the top-level encrypted/plain script section inside
each owned MOB's declared root. It preserves condition order and nested calls,
then selects only whole condition lists that the native adapter supports.
Selection rotates through maps so the 120-list cap is not filled by one region.
Use `--quest-limit 0` to include every supported list, or a positive cap.
Inputs retain each MOB's SHA-256, script name, block index, actor/group bindings
and iterator names.

The fixtures supply positions, HP, death states, lever states and quest flag
values, group memberships, time, money, quest bags and controlled area geometry. They include null
actors, separated actor pairs, rectangle/circle edges, empty/all-dead/mixed
groups and flag/lever transitions. Native area containers are preallocated;
their construction and lookup run, while heap allocation is outside the scope.
Environment gates include both sides of authored numeric thresholds, absent and
present items, and mixed literal flag prerequisites. These input candidates
are independent of the observed original results.
The area shapes are supplied fixtures, not recovered map initialization.
These are controlled condition replays, not saved
campaign playthroughs or evidence that all supplied states are reachable.
Parsing and object resolution inside either complete game are outside this
contract. Unsupported calls or bindings skip the whole condition list and are
counted in `inputs.json` under `authored_quests.skipped`; they never become
automatically true conditions. Full quest bodies, carried inventory and transfers,
dynamic group construction, thread scheduling, co-op adaptations and reward/save continuity
still need additional native coverage.

## Results and failures

Exit codes:

| Code | Meaning |
|---|---|
| `0` | Every selected observation matches; check `repeatability.verified` for repeated-run verification |
| `1` | At least one behavioral difference was captured |
| `2` | Setup/capture failed, output was incomplete, reference was unsupported, or repeat captures disagreed |

Each result directory contains:

- `report.md`, `report.json` and `junit.xml`: per-scenario results and first differences.
- `inputs.json`: exact input bytes, reference identity and comparison contracts.
- `original-N.json` and `remake-N.json`: complete captures from each repetition.
- `runtime/`, `harness/`, `runtime-source.json`, `tool-source.json`: tested game/native harness snapshots and hashes.
- Capture/import logs and isolated profiles.
- `reproduce.sh`: repeat the same inputs against the current source in a new directory.

Existing result directories are never overwritten. No difference is
automatically approved. A complete run can exit `1` because of an already
documented approximation; that remains visible until it is addressed.

Godot can initially parse autoload scripts before a clean project's textures
and fonts have been imported. The runner retains those bootstrap diagnostics,
then requires a clean second import and clean capture logs. A nominal zero
process exit with script/runtime errors does not count as a successful capture.

The initial [validation record](validation/original-parity-2026-10-20/README.md)
records five hit-probability differences and a live mutation control.
The [expanded validation](validation/gameplay-suite-2026-10-20/README.md)
records 430 scenarios, two captures per side and a dialogue-gate mutation control.
The [quest, Astral and body validation](validation/quest-parity-2026-10-20/README.md)
records the initial independent campaign captures and 72 differences.
The [subsequent fixes and expanded validation](validation/parity-fixes-2026-10-20/README.md)
resolve all 72 and extend coverage to 3,511 matching scenarios, including group
conditions, registered quest areas and varied health-state sequences.
The [quest progression expansion](validation/quest-depth-2026-10-20/README.md)
adds 862 comparisons, including 360 more authored condition lists and persistent
command sequences in both campaigns. It records the wait, inventory-query and
loot-query fixes, save compatibility checks, and the complete failure disposition.

## Extend the suite

1. Identify the original routine and its calling conditions for the pinned
   executable. Record what is supplied at the boundary and what instructions
   remain under test.
2. Add inputs to `cases.py`. Include a meaningful edge case and avoid expected
   results or a reimplementation of the game formula.
3. Capture original observations in `native.py`, then independently call the
   corresponding production method in `remake_trace.gd`.
4. Add a contract with coverage limits and any narrowly justified tolerance.
   Update completion validation for the new trace shape.
5. Run both sides repeatedly and demonstrate a relevant deliberately introduced
   mismatch in an isolated copy. Keep the unmodified source as the reference
   remake under test.

### Extension families

A family can also live in its own files without editing the shared runner
(`tools/parity/extensions.py` discovers them in sorted order):

- `cases_ext_<name>.py`: `contracts(campaign)` (empty for an unqualified
  executable), `scenarios(seed, fuzz)`, optional `STEP_COUNTS`,
  `validate(case, steps, role)` and `authored(game_dir, limit)` for rows built
  from the owned installation under `--authored-quests`.
- `native_ext_<name>.py`: `CAPTURES = {kind: function}`.
- `remake_ext_<name>.gd`: staged as `res://tools/parity_ext/<name>.gd`, with
  `kinds()` and `capture(kind, data, trace)`; `trace` exposes the shared quest
  fixtures of `remake_trace.gd`.
- `test_ext_<name>.py` and `docs/original-parity-<name>.md`.

A kind may be declared only once and may not replace a core family.

Current families (seed 20261020, fuzz 12; counts are match / differ, base
game first, then Lost in Astral where qualified):

| Family | Kinds | Scenarios | Base | Astral | Details |
|---|---|---|---|---|---|
| Quest query builtins | `quest_query` | 123 | 71 / 52 | 71 / 52 | [quest-query](original-parity-quest-query.md) |
| Quest commands | `quest_cmd_groups`, `_gsvar`, `_items`, `_journal`, `_levers` | 143 | 110 / 33 | not qualified | [quest-commands](original-parity-quest-commands.md) |
| Quest trigger scheduling | `quest_scheduler` | 66 | 4 / 62 | not qualified | [quest-scheduler](original-parity-quest-scheduler.md) |
| Dialogue triggers | `dialogue_topics`, `_zone`, `_merc`, `_complete` | 158 | 139 / 19 | not qualified | [dialogue](original-parity-dialogue.md) |
| NPC script commands | `npc_motivation`, `npc_diplomacy`, `npc_alarm` | 213 | 137 / 76 | 137 / 76 | [npc-commands](original-parity-npc-commands.md) |
| NPC AI decisions | `npc_ai_fear`, `_suspicion`, `_target_score`, `_motivation` | 182 | 98 / 84 | not qualified | [npc-ai](original-parity-npc-ai.md) |
| Perception triggers | `perception_group`, `perception_ticks` | 452 | 393 / 59 | 384 / 32 (`perception_group` only, 416) | [perception-triggers](original-parity-perception-triggers.md) |

Every family was shown to fail on a mutated scratch copy of the remake (see
each page). Differences are findings about the remake, not harness errors.
With `--authored-quests`, families that define `authored()` add rows built from
the owned installation's MOB conditions (for example 316 perception rows in
the base game; `--case perception_` then gives 670 / 98 of 768).

Full runs on 2026-10-21, both sides repeatable: base game 3094 scenarios,
2709 match, 385 differ; Lost in Astral 1567 scenarios, 1407 match, 160 differ.
Every core family still matches completely; all differences are in the
extension families above.

For target ordering, the supplied terrain must have one ground height per XY
coordinate. Ambiguous fixtures are rejected instead of producing misleading
game differences.

The next original-comparison priorities are damage/armour, full movement paths,
complete quest-thread lifecycles and save/load state continuity. These need additional
native adapters and state fixtures. The gameplay regression suite already tests
selected remake behavior in those areas; those assertions do not establish
equivalence to the original executable.
