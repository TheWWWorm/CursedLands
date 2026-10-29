# Gameplay regression suite

`tools/parity/gameplay.py` runs 821 registered test configurations across 20
areas, using 618 scripts (the focused manifest was folded into this catalog
on 2026-10-29; its cases carry a `focused` ID, see
[the focused checks](regression-checks.md)). It combines existing regression programs with item,
effect, theft, crafting, side-quest, localization and travel boundary tests.
A registration selects a script, campaign
and arguments; some scripts are exercised in both campaigns or in several
save/load scenarios. It stages the game and test sources, launches each
configuration in a separate process, and retains logs and reproduction inputs.

These are **remake regressions**. With `--with-original`, the runner also runs
the independent [original-executable suite](original-parity.md).
The reports keep those two kinds of evidence separate.

The [LiA quest checkpoint command](original-checkpoints.md#run-the-lia-quest-checks)
combines 75 selected gameplay programs with independently recorded
patched-original saves, including the existing interaction/return regressions. It covers
the numbered LiA campaign route through the ending, early Portal and torch
cellar, all three Rod of Life fragments, Кель's death and rescue, route gates,
map points, missing prerequisites, save/reload continuation, and every map's
quest state with each externally granted flag set before or after the first
visit. The
[campaign qualification](validation/lia-campaign-checkpoints-2026-10-23.md)
records prepared chapter seams, native comparisons and their limits. Repeated
`--case` filters combine selections.

The [focused recurring-report command](regression-checks.md) selects recent issue
contracts and submits graphical work through GPU Lab. The October 25 changes
registered eleven additional gameplay programs and the performance-log check in
this full catalog. Catalog size
is available coverage, not a claim that every configuration was run for this patch.

## Run

Requirements: Linux, Python 3.11+, Godot 4.7, and owned base-game and Lost in
Astral installations. The regression runner itself uses only Python's standard
library. The 77 rendered configurations also require an explicitly selected
private X display supplied by GPU Lab; the other 416 run headlessly.
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

# Programs run in parallel (default --jobs auto); each keeps its own process
# and profile. --jobs 1 runs them one at a time.
python3 tools/parity/gameplay.py \
  --game-dir /path/to/base-game --astral-dir /path/to/lost-in-astral \
  --godot /path/to/godot --out /tmp/lia-quests --case lia_

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
rendered configurations produce explicit errors, not headless passes. On the shared workstation, submit the rendered command through GPU Lab and use
its assigned display; do not start another X server or use the physical desktop.
The runner defaults to OpenGL compatibility on that display. A fixture can
declare `rendering_method` to require Forward+ or Mobile; a renderer fallback
is then an error. It does not change the machine's display configuration.

Missing expansion data produces explicit errors for expansion programs.
It is not counted as skipped or passed. Base and expansion tests use different
asset roots, and each process confirms the campaign it actually loaded.

## Coverage

| Area | Programs | Examples |
|---|---:|---|
| Quests | 146 | Predicates, triggers, traps, numeric precision, wait timing and old/new save continuity in both campaigns, area save compatibility, quest items, rewards, actor removal, group levers, chapter transitions, captivity and escape, Catacombs, dragon timers, all 28 installed base side-quest archives, and the LiA campaign through its ending, map-point matrix, three-fragment/Kel-rescue route, pending final-battle save repair, and every LiA map's quest state with each externally granted flag set before or after the first visit |
| Creatures | 12 | AI sleep/wake eligibility, senses, reaction recipients, witnessed attacks, hostility snapshots, authored creature spell damage, actor lifetime, peasant help and registry queries |
| Animation | 21 | Attack clips across both campaigns' creatures, gait continuity, moving attacks/casts, rendered first-person shadows, initial and loaded paused poses, original dialogue poses on peers and attack stance |
| Effects | 18 | Model attachment points and projectile origins in both campaigns, delayed effects, pause/lifetime/teardown, repeated spells, healing, fire and tornado particle kernels, exact duration boundaries and overlapping status expiry |
| Stealth | 8 | Invisibility, silence, pursuit, remembered targets, loopback peers, perception, partial visibility, theft completion/cancellation, quest pockets and personal hostility |
| Commands | 27 | Combat inputs, priority/replacement, held actions, interactions, retries with packet loss/reordering, spell shortcuts, bow release, first-person selection, touch picking and travel confirmation/cancellation |
| Pathing | 19 | Turn refinement, topology, ray boundaries, relocation, route previews, narrow passages, client placement, lift capacity, direct movement and campaign-map reveal |
| Spells | 9 | Stamina waits and regeneration, single acknowledgements, training requirements on host/guest, execution-time revalidation, paused construction transactions, seeded shop generation in both campaigns |
| Inventory | 30 | Repair, exchanges, duplicate copies, private purses, stale stock, equipment/runes, nine crafting recipes per campaign, belt/spell capacities, recruitment, network loot, real camp UI and persistence |
| Progression | 5 | Training purchase orders, refunds and rank limits, guest training, XP distribution, downed companion XP and revival |
| Party | 4 | Wounded pets, disconnected ownership, companion/pet chapter substitution, travel, save/load and revival camera |
| Persistence | 16 | Hostility, wounds, stamina, commands, actor references, frozen clock, casts, taming, pets, potions, wall effects, profile seeds and network save choices |
| Combat | 6 | Hit rolls, backstabs, ranged attacks, wounds, severance, healing, resurrection, body cache and wisp spells |
| Network | 5 | Seeded snapshot codec, packet loss and reordering, stale generations, perception lists, generated large campaign documents and acknowledgement batching |
| Dialogue | 12 | Authored topics, walking/staging, cues, captive/elder/guard routes, Nalo rescue and Shaina disguise |
| Co-op | 50 | Fresh heroes, malformed origins, classes/roles, ownership, renaming/reconnect, personal/shared checkpoints, chapter state, solo return and network world transfers |
| Settings | 22 | Profiles, controls, camera, graphics presets, audio routing/echo, EN/RU/DE choices and every remake translation's format arguments |
| Interface | 41 | Buff icons, loading progress/cover, tooltip lifetime, side-quest scrolling and localized quest/wiki text |
| Arena | 41 | Recruitment, economy, alliances, deployment, shop, round settlement, saves, health/damage, species, standings, tournament and bot planning |

An assertion count is a count of checks, **not games played or unique
features**. Large parameter sweeps contribute many checks. Several optimized
kernels are compared against their retained GDScript implementation; that is
useful regression evidence but is not original-executable parity.

The catalog is `tools/parity/gameplay_catalog.json`. It declares each script,
campaign, required baseline files, completion marker, minimum check count,
arguments, timeout, display mode and quick/full classification. Expansion-specific scripts
and shared model sweeps are explicitly assigned their asset set. An entry with
`focused` is also a case of `tools/check_regressions.py` under that short ID;
an entry that lists `texts` takes the original localized archives
(`--texts-en` / `--texts-ru` / `--texts-de`) as `{texts_xx}` arguments, and is
reported as missing data when one is not supplied.

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
peers on fixed fixture ports. Programs run in parallel: `--jobs auto` (the
default) runs one per three CPU threads, at most as many as free memory holds
at about 4.5 GiB each beyond an 8 GiB reserve, and starts the next program only
while that much memory is still free. Programs whose script (or a script it
extends or preloads) opens sockets run one at a time, as do rendered programs
sharing the private display. Ctrl-C or a runner error stops every running
program. The report keeps the selection order. Private
player saves and preferences are neither copied nor changed.

Process control (ending a program on its first runtime diagnostic or at its
timeout, the summary-line contract and the 1280×800 rendered window) lives in
[`tools/parity/process.py`](../tools/parity/process.py) and is shared with the
focused runner, which reads the same catalog, so the two cannot drift;
`tools/raise_min_checks.py` raises `min_checks` from green reports of either runner.

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
UI interactions, geometry/pixel assertions and captures under real OpenGL or
their explicitly required Forward+ renderer.
Neither establishes overall visual quality, audible fidelity, external
Internet reliability or a complete ordinary campaign playthrough.

`animation/first_person_shadows` and `animation/first_person_shadows_astral`
compare rendered ground-shadow pixels with the complete original figure at
three running-leg phases during running, attacking and casting. They submit
the final composed pose after the early camera alignment, so an unchanged
native attack/cast shadow cannot pass by matching only the node transforms.
The [retained verification](validation/first-person-shadow-2026-10-21/results.json)
includes the unchanged-source negative control, before/after captures, and
separate baseline comparisons for the broader camera/coverage failures.

`animation/first_person_reflections` and its expansion configuration compare
the native figure through the production mirror camera transform and cull
mask. They check the visible face, rigid/skinned poses, severed heads, shadow
quality independence and restoration of ordinary camera layers. The retained
[first-person and Screen results](validation/first-person-screen-2026-10-21/results.json)
also cover exhausted walking with held sprint input, preset/AA independence,
localized Screen dropdowns and larger bounded popups. Separate Windows
D3D12/Wine checks verify generated presentations in all three display modes;
bypassing the new borderless path reproduces zero generated frames. Those
checks used NVIDIA hardware and do not qualify native Windows or a Radeon.

`commands/self_cast_bursts` and `commands/self_cast_bursts_astral` inject spell
key events in all three camera modes, step native casts/effects, and check
selection, command counts, stamina costs and the halfway repeat boundary.
They cover spells already selected through a shortcut or HUD, distinct spell
shortcuts and configured variants, queued casts, stamina waits, simulated
delayed delivery and the acknowledgement/snapshot gap, replica start timestamps, explicit modified
shortcuts, and translated help wrapping in EN/RU/DE. The delayed-delivery
fixture does not establish real network transport behavior.
The [retained results](validation/self-cast-bursts-2026-10-21/results.json)
include the seven passing regressions and the staged guard-bypass control.
The [preselected-spell results](validation/self-cast-bursts-2026-10-21/preselected-results.json)
retain the expanded 166-check fixture passing in both campaigns with unchanged
production code.

Tests requiring private saves, manual input or unbounded play sessions are not
automatically included. A fixture that freezes the session and advances the
script VM directly lets few frames pass, so the world `Game.attach_world`
queued for deletion stays loaded. After each map change, call
`tools/tests/world_release.gd` (as `lia_kel_support.gd`'s `freeze()` does) and
check that only one world remains. Add a self-contained fixture with an explicit numeric
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
The [quest progression record](validation/quest-depth-2026-10-20/README.md)
records subsequent quest, dialogue and persistence checks alongside the separate
original-executable comparisons.
