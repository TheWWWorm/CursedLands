# Gameplay regression suite

`tools/parity/gameplay.py` runs 101 registered test configurations across 14
areas. It combines existing regression programs with new item-state and
effect-duration boundary matrices. A registration selects a script, campaign
and arguments; some scripts are exercised in both campaigns or in several
save/load scenarios. It stages the game and test sources, launches each
configuration in a separate process, and retains logs and reproduction inputs.

These are **remake regressions**. With `--with-original`, the runner also runs
the independent [430-scenario original-executable suite](original-parity.md).
The reports keep those two kinds of evidence separate.

## Run

Requirements: Linux, Python 3.11+, Godot 4.7, and owned base-game and Lost in
Astral installations. The regression runner itself uses only Python's standard
library. The optional original comparison additionally requires
`tools/parity/requirements.txt` in the Python environment.

From the repository root:

```sh
python3 tools/parity/gameplay.py \
  --game-dir /absolute/path/to/base-game \
  --astral-dir /absolute/path/to/lost-in-astral \
  --godot /absolute/path/to/godot \
  --out /absolute/path/to/new-results

# Run both regressions and original-instruction comparisons.
.venv-parity/bin/python tools/parity/gameplay.py \
  --game-dir /path/to/base-game --astral-dir /path/to/lost-in-astral \
  --godot /path/to/godot --out /tmp/gameplay-with-original \
  --with-original

# Inspect the catalog without launching Godot or requiring assets.
python3 tools/parity/gameplay.py --list

# Combine category filters.
python3 tools/parity/gameplay.py \
  --game-dir /path/to/base-game --astral-dir /path/to/lost-in-astral \
  --godot /path/to/godot --out /tmp/quest-path-checks \
  --category quests --category pathing

# Narrow to one program (substring), or use --quick for smaller fixtures.
python3 tools/parity/gameplay.py \
  --game-dir /path/to/base-game --godot /path/to/godot \
  --out /tmp/alert-check --case creatures/creature_alerts

# Exercise inventory, spells and save/load in both campaigns.
python3 tools/parity/gameplay.py \
  --game-dir /path/to/base-game --astral-dir /path/to/lost-in-astral \
  --godot /path/to/godot --out /tmp/items-spells-saves \
  --category inventory --category spells --category persistence

# Repeat the retained program selection against the current source.
/path/to/results/reproduce.sh /tmp/gameplay-repeat

# Test the runner and comparator, including negative controls; no game needed.
python3 -m unittest discover -s tools/parity -p 'test_*.py' -v
```

Use a new output directory for every run. Existing results are never
overwritten. `--seed` defaults to `20261020`; individual programs may also use
their own fixed seeds. Real-time animation/network sessions are not claimed
to be deterministic traces. `--timeout` overrides the default per-program
timeout. `--game-source` tests a different game checkout using this runner's
test scripts; both are copied and hashed.

Missing expansion data produces explicit errors for expansion programs.
It is not counted as skipped or passed. Base and expansion tests use different
asset roots, and each process confirms the campaign it actually loaded.

## Coverage

| Area | Programs | Examples |
|---|---:|---|
| Quests | 15 | Dead/hero predicates, co-op triggers and traps, quest carriers, inventory lifecycle, rewards in both campaigns, actor removal, group lever operation, transition saves, whole-party guard escape, Catacombs lift cycles, dragon story timers |
| Creatures | 7 | AI sleep/wake eligibility, senses, reaction recipients, witnessed attacks, hostility snapshots, authored creature spell damage, native unit-state publication and actor lifetime |
| Animation | 8 | Attack clips across both campaigns' creatures, gait continuity, moving attacks/casts, initial and loaded paused poses, original dialogue poses on peers |
| Effects | 11 | Model attachment points and projectile origins in both campaigns, delayed effects, pause/lifetime/teardown, repeated spells, healing, fire and tornado particle kernels, exact duration boundaries and overlapping status expiry |
| Stealth | 6 | Invisibility, silence, patrol escape versus scripted pursuit, remembered targets, real loopback peers, perception batches, partially exposed units/corpses, hidden presentation |
| Commands | 8 | Combat-state inputs, priority/replacement, held actions, interaction dispatch, consumed mechanisms, retries with simulated packet loss/reordering, spell shortcuts, moving bow release and aim |
| Pathing | 7 | Turn refinement, static/dynamic topology, ray boundaries, relocation search, preview lengths/contact cutoffs, actual narrow passages |
| Spells | 8 | Stamina waits and regeneration, single acknowledgements, training requirements on host/guest, execution-time revalidation, paused construction transactions, seeded shop generation in both campaigns |
| Inventory | 9 | Repair and exchange batches, duplicate copies, private purses, stale stock, unique equipment, legacy rune migration, construction fees, wear/charge conservation and disk round trips |
| Progression | 5 | Training purchase orders, refunds and rank limits, guest training, XP distribution, downed companion XP and revival |
| Party | 2 | Wounded pets, disconnected ownership, companion/pet chapter substitution, travel and save/load |
| Persistence | 9 | Hostility, wounds, stamina, commands, actor references, frozen world clock, pending casts, all taming stages, pet identity, consumed potions and alternating wall-effect checkpoints |
| Combat | 3 | Direct hit rolls and backstabs, authored ranged attacks, wounds, severance, healing, resurrection and body-cache invalidation |
| Network | 3 | Seeded snapshot codec, packet loss and reordering, stale generations, perception lists, generated large campaign documents and acknowledgement batching |

An assertion count is a count of checks, **not games played or unique
features**. Large parameter sweeps contribute many checks. Several optimized
kernels are compared against their retained GDScript implementation; that is
useful regression evidence but is not original-executable parity.

The catalog is `tools/parity/gameplay_catalog.json`. It declares each script,
campaign, required baseline files, completion marker, minimum check count,
arguments, timeout and quick/full classification. Expansion-specific scripts
and shared model sweeps are explicitly assigned their asset set.

## Isolation and failure handling

Every test starts with a fresh XDG profile containing:

```ini
confine_mouse=0
show_fps=1
volume_sfx=0
volume_stream=0
volume_voice=0
```

The bootstrap checks those preferences before running the test. Autosave,
tutorials and public network discovery are disabled. Network tests use local
peers; programs run sequentially to avoid conflicting fixture ports. Private
player saves and preferences are neither copied nor changed.

The bootstrap preserves the ordinary `--tool` scene layout so a separate
simulation worker uses the same RPC paths as its frontend. Real-time programs
retain their normal clock; they are not forced through Godot's fixed-FPS
capture mode.

A pass requires the selected script's unique completion marker, enough checks,
zero failed assertions, a successful exit, the correct campaign/profile, and
no runtime/script errors. The runner promptly terminates its test process
group on a script error or timeout. It continues with the remaining programs.
An interrupted or incomplete collection stays incomplete in both JSON and
JUnit; it cannot become a green partial suite.

| Exit | Meaning |
|---|---|
| `0` | All selected programs completed successfully, including optional original comparison |
| `1` | Assertion failures or original-executable differences |
| `2` | Setup, timeout, runtime or incomplete-capture error |

Results include `report.md`, `report.json`, `junit.xml`, the source snapshot
and hashes, required-asset hashes, `selection.json`, per-program logs and
profiles, and `reproduce.sh`. When requested, `original/` contains the separate
native comparison report. Reproduction uses the retained selection rather
than silently adopting later catalog changes.

## Limits and extension

Headless animation/effect checks inspect state, clips, transforms, attachment
points and simulation values. They do not qualify rendered pixels, visual
quality, sound, external Internet sessions or a full ordinary campaign
playthrough. Render-only assertions in existing scripts remain outside this
headless coverage.

Tests requiring private saves, manual input or unbounded play sessions are not
automatically included. Add a self-contained fixture with an explicit numeric
summary and campaign assignment before registering it. Keep a failing
behavior visible while investigating; never lower coverage or change an
expected outcome merely to get a green run.

The transport and fallen-companion programs now create their own deterministic
campaign or prepared recruitment fixture. Their optional `--route-save` input
remains available for separate diagnostics; the catalog never supplies a
player's save. Taming tests call the existing production transition directly;
they do not establish that a charm spell is available in ordinary shop stock.

The new item matrix checks 150 wear/charge combinations per campaign, including
duplicate storage and repeated repair/recharge. The duration matrix checks
signed counter boundaries, exact save values, the existing 16-bit snapshot
representation, client presentation versus authority expiry, and overlapping
effects. Neither matrix is labelled as an original-executable comparison.

The [initial validation record](validation/gameplay-suite-2026-10-20/README.md)
and [expansion record](validation/gameplay-expansion-2026-10-20/README.md)
retain qualification, fixture corrections and deliberately injected failures.
