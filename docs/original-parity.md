# Original-engine comparison suite

`tools/parity/run.py` executes the original game's x86 instructions and the
remake's production methods in separate processes, supplies the same authored
inputs, and compares their observations. It reports the first differing step
and field for each scenario. This makes small ordering, rounding and boundary
differences reproducible.

This first version covers **bounded subsystems**. It does not replay a whole
Windows game session or establish campaign equivalence.

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
The qualified reference is the GOG English base-game executable with SHA-256:

```text
d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8
```

The runner rejects other executables **before executing any native address**.
This reference has no additional patches. Other languages, releases and patch
sets need separately verified addresses and reference identities.

The default suite has 126 scenarios: 78 authored cases and 12 seeded cases in
each of four families. The default seed is `20261020`. Each side runs twice in
fresh captures; differing repeat captures are an error, even if one pair
matches. The run creates a private source snapshot and fresh profiles with the
cursor free, FPS enabled and all three audio volumes muted. It never reads or
copies a player's settings.

```sh
# List inputs without Godot, Unicorn or game data.
python3 tools/parity/run.py --list

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
| Interaction reach | Exact float32 bits for loot, steal and lever distances with supplied radii | No route planning, inventory transfer or lever state change |
| Attack decision | Boolean hit decisions at zero-spread and aimed-attack boundaries | Synthetic attributes; no damage, armour, backstab or RNG equivalence |
| Hit probability | Original hit decisions enumerated over every supplied roll residue, weighted uniformly, versus the remake probability query | Unaimed attacks with supplied attributes; no whole combat or RNG stream replay |

The machine-readable contracts in `tools/parity/cases.py` list native addresses,
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
`Combat.attack_hits` and `Combat.hit_chance`. It receives input fixtures only;
the original observations and comparator are not staged into its project.

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
- `runtime/`, `runtime-source.json`, `tool-source.json`: tested source snapshot and hashes.
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

For target ordering, the supplied terrain must have one ground height per XY
coordinate. Ambiguous fixtures are rejected instead of producing misleading
game differences.

The next coverage priorities are damage/armour, blocked movement paths,
script/quest transitions and save/load state continuity. These need additional
original adapters and state fixtures; the current suite does not cover them.
