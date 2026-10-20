# Gameplay regression suite

`tools/parity/gameplay.py` runs 283 registered test configurations across 19
areas, using 223 scripts. It combines existing regression programs with item,
effect, theft, crafting, side-quest, localization and travel boundary tests.
A registration selects a script, campaign
and arguments; some scripts are exercised in both campaigns or in several
save/load scenarios. It stages the game and test sources, launches each
configuration in a separate process, and retains logs and reproduction inputs.

These are **remake regressions**. With `--with-original`, the runner also runs
the independent [original-executable suite](original-parity.md).
The reports keep those two kinds of evidence separate.

## Run

Requirements: Linux, Python 3.11+, Godot 4.7, and owned base-game and Lost in
Astral installations. The regression runner itself uses only Python's standard
library. The 43 rendered configurations also require an explicitly selected
private X display, such as Xvfb; the other 240 run headlessly.
The optional original comparison additionally requires
`tools/parity/requirements.txt` in the Python environment.

From the repository root:

```sh
python3 tools/parity/gameplay.py \
  --game-dir /absolute/path/to/base-game \
  --astral-dir /absolute/path/to/lost-in-astral \
  --godot /absolute/path/to/godot \
  --out /absolute/path/to/new-results --display headless

# Run both regressions and original-instruction comparisons.
.venv-parity/bin/python tools/parity/gameplay.py \
  --game-dir /path/to/base-game --astral-dir /path/to/lost-in-astral \
  --godot /path/to/godot --out /tmp/gameplay-with-original \
  --render-display :91 --with-original

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
  --category inventory --category spells --category persistence --display headless

# Only rendered UI checks, on an already running private X server.
python3 tools/parity/gameplay.py \
  --game-dir /path/to/base-game --astral-dir /path/to/lost-in-astral \
  --godot /path/to/godot --out /tmp/rendered-gameplay \
  --display rendered --render-display :91

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

`--render-display` never defaults to the user's desktop. Without it, selected
rendered configurations produce explicit errors, not headless passes. An Xvfb
server can be started with `Xvfb :91 -screen 0 1920x1200x24 -nolisten tcp`.
The runner uses OpenGL compatibility on that display. It does not install
Xvfb or change the machine's display configuration.

Missing expansion data produces explicit errors for expansion programs.
It is not counted as skipped or passed. Base and expansion tests use different
asset roots, and each process confirms the campaign it actually loaded.

## Coverage

| Area | Programs | Examples |
|---|---:|---|
| Quests | 28 | Predicates, triggers, traps, numeric precision, area save compatibility, quest items, rewards, actor removal, group levers, chapter transitions, captivity and escape, Catacombs, dragon timers and all 28 installed base side-quest archives |
| Creatures | 12 | AI sleep/wake eligibility, senses, reaction recipients, witnessed attacks, hostility snapshots, authored creature spell damage, actor lifetime, peasant help and registry queries |
| Animation | 14 | Attack clips across both campaigns' creatures, gait continuity, moving attacks/casts, initial and loaded paused poses, original dialogue poses on peers and attack stance |
| Effects | 14 | Model attachment points and projectile origins in both campaigns, delayed effects, pause/lifetime/teardown, repeated spells, healing, fire and tornado particle kernels, exact duration boundaries and overlapping status expiry |
| Stealth | 8 | Invisibility, silence, pursuit, remembered targets, loopback peers, perception, partial visibility, theft completion/cancellation, quest pockets and personal hostility |
| Commands | 16 | Combat inputs, priority/replacement, held actions, interactions, retries with packet loss/reordering, spell shortcuts, bow release, first-person selection, touch picking and travel confirmation/cancellation |
| Pathing | 14 | Turn refinement, topology, ray boundaries, relocation, route previews, narrow passages, client placement, lift capacity, direct movement and campaign-map reveal |
| Spells | 8 | Stamina waits and regeneration, single acknowledgements, training requirements on host/guest, execution-time revalidation, paused construction transactions, seeded shop generation in both campaigns |
| Inventory | 26 | Repair, exchanges, duplicate copies, private purses, stale stock, equipment/runes, nine crafting recipes per campaign, belt/spell capacities, recruitment, network loot, real camp UI and persistence |
| Progression | 5 | Training purchase orders, refunds and rank limits, guest training, XP distribution, downed companion XP and revival |
| Party | 3 | Wounded pets, disconnected ownership, companion/pet chapter substitution, travel, save/load and revival camera |
| Persistence | 12 | Hostility, wounds, stamina, commands, actor references, frozen clock, casts, taming, pets, potions, wall effects, profile seeds and network save choices |
| Combat | 4 | Hit rolls, backstabs, ranged attacks, wounds, severance, healing, resurrection, body cache and wisp spells |
| Network | 5 | Seeded snapshot codec, packet loss and reordering, stale generations, perception lists, generated large campaign documents and acknowledgement batching |
| Dialogue | 11 | Authored topics, walking/staging, cues, captive/elder/guard routes, Nalo rescue and Shaina disguise |
| Co-op | 48 | Fresh heroes, malformed origins, classes/roles, ownership, renaming/reconnect, personal/shared checkpoints, chapter state, solo return and network world transfers |
| Settings | 14 | Profiles, controls, camera, graphics presets, audio routing/echo, EN/RU/DE choices and every remake translation's format arguments |
| Interface | 19 | Buff icons, loading progress/cover, tooltip lifetime, side-quest scrolling and localized quest/wiki text |
| Arena | 22 | Recruitment, economy, alliances, deployment, shop, round settlement, saves, health/damage, species, standings, tournament and bot planning |

An assertion count is a count of checks, **not games played or unique
features**. Large parameter sweeps contribute many checks. Several optimized
kernels are compared against their retained GDScript implementation; that is
useful regression evidence but is not original-executable parity.

The catalog is `tools/parity/gameplay_catalog.json`. It declares each script,
campaign, required baseline files, completion marker, minimum check count,
arguments, timeout, display mode and quick/full classification. Expansion-specific scripts
and shared model sweeps are explicitly assigned their asset set.

`tools/parity/player_features.json` maps 35 player-facing feature groups and
all 48 verbs in the campaign authority dispatchers to tests or explicit gaps.
The harness checks that the command inventory stays complete. This is an
inventory, not a code-coverage percentage or proof that every path works.
Mod distribution and non-Linux platforms have no configurations in this run.
Each report's `features.md` shows linked passes, failures, errors and tests not
run, alongside the scope and remaining gaps.

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
points and simulation values. Rendered configurations execute their specific
UI interactions, geometry/pixel assertions and captures under real OpenGL.
Neither establishes overall visual quality, audible fidelity, external
Internet reliability or a complete ordinary campaign playthrough.

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
retain earlier qualification. The
[player-encounter audit](validation/player-encounters-2026-10-20/README.md)
records the broader coverage, current failures, corrected fixtures and
deliberately injected failures.
