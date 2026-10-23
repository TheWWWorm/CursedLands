# Quest checkpoints from original saves

`tools/parity/checkpoints.py` compares recorded quest steps with the original
game. Each reference contains the original's before/after state and the
operation performed between them. The remake restores the declared before
fixture, performs that operation and must match the independently recorded
original result. Expected results are never passed to the remake process.

This complements the [bounded original-engine comparisons](original-parity.md)
and the [gameplay regression suite](gameplay-testing.md). The latter also checks
passability, missing prerequisites, save/load and duplicate rewards. Matching an
original bug is not proof that a quest is passable: the Portal cellar regression
has a documented, intentional compatibility repair.

## Run the base-game quest checks

Use an owned Evil Islands / Cursed Lands installation:

```sh
BASE_GAME=/path/to/EvilIslands \
GODOT=/path/to/godot-4 PYTHON=/path/to/parity-venv/bin/python \
  tools/parity/run_base_quests.sh /path/to/NEW-evidence-directory
```

This selects all 36 `base_campaign_` configurations, the side-quest lifecycle
and lever-save regressions, and every `base_` original checkpoint. The native
references run twice in separate profiles. The output directory must be new;
a failed gameplay assertion or original comparison produces a nonzero exit.
Python needs the parity environment's Unicorn dependency for native-save work.

The [base-campaign qualification](validation/base-campaign-checkpoints-2026-10-23.md)
maps all 92 named campaign quests and 28 installed side archives to their
completion checkpoints. It records prepared chapter boundaries, selected
alternate branches, save/load coverage and the limits of accelerated tests.

## Run the LiA quest checks

Use an owned base game and a Lost in Astral installation with official patches
**1.01, then 1.02** applied. The remake contains the corresponding compatibility
corrections. New native references identify the executable that produced them;
the 1.02 reference hash is
`9ecd475f5776681b8ffe1a8bb05cf67fe7adcceb62d0949135261ed7d3616c12`.

```sh
BASE_GAME=/path/to/EvilIslands \
ASTRAL_GAME=/path/to/patched-LostInAstral \
GODOT=/path/to/godot-4 PYTHON=/path/to/parity-venv/bin/python \
  tools/parity/run_lia_quests.sh /path/to/NEW-evidence-directory
```

This runs all `lia_kel_` and `lia_campaign_` gameplay cases, the existing
arrival, Revenge, Slave Lists return and tomb-exit regressions, the
interaction-callback regression, and every `lia_` native checkpoint.
The campaign cases include late Jigran through the ending and all four region
maps. Each native checkpoint is replayed twice in
fresh profiles. The directory must not exist: previous evidence is never
silently replaced. The gameplay report and native checkpoint report have
separate results and scopes. A nonzero exit means a failed check or capture.

Run only selected original checkpoints:

```sh
python tools/parity/checkpoints.py run \
  --astral-dir /path/to/patched-LostInAstral --godot /path/to/godot-4 \
  --name lia_portal --work-dir /path/to/NEW-checkpoint-evidence
```

Each run retains the exact selected references, source and asset hashes, logs,
JSON results, isolated profiles and remake before/after saves. Its
`reproduce.sh /path/to/NEW-directory` repeats the retained reference selection
against the selected source checkout. `--game-source` selects another remake
`game/` tree. `--repeat 1` is useful for diagnosis but does not verify
repeatability. All test profiles leave the cursor free, show FPS and mute SFX,
stream and voice audio; the engine also uses the Dummy audio driver.

## Reading original saves

`tools/parity/original_save.py` reads a save slot (`saves/saveq`,
`saves/savea`, ...). It unpacks the files with the verified **base-game**
executable's decoder in Unicorn and verifies each checksum. It reports zone,
party names, money, and GS variables at zone entry (`scenario.sav`) and live
(`mission.sav`). Lost in Astral uses the same save format. The decoder executable
is distinct from the executable that actually ran the recorded game.

```sh
.venv-parity/bin/python tools/parity/original_save.py \
  --game-exe /path/to/EvilIslands/game.exe /path/to/LostInAstral/saves/saveq
```

Item containers and unit-stat blocks are not fully interpreted. Inventory,
archived parties and physical object state needed by an action must be recorded
as explicit fixtures and independently observed through native probes. These
are bounded before-state reconstructions, not universal native-save imports.

## Record a checkpoint

1. Prepare the original in an isolated installation/profile. Record every cheat
   or prerequisite supplied. Quicksave immediately before the action and copy
   `saves/saveq` to a retained `before/` directory.
2. Perform the action, allow its watchers to run, then save/copy `after/`.
   Close the console before F5 and verify the save changed. Confirm the game was
   running: an inadvertently paused engine can change a lever without running
   its quest trigger.
3. Decode both slots, inspect the actual outcome and record the reference:

```sh
.venv-parity/bin/python tools/parity/checkpoints.py make \
  --game-exe /path/to/EvilIslands/game.exe \
  --source-exe /path/to/patched-LostInAstral/game.exe \
  --campaign lost_in_astral \
  --before /path/to/before --after /path/to/after \
  --name lia_example --note "Describe the actual recorded action and cheats" \
  --fixture /path/to/fixture.json --probes /path/to/probes.json \
  --step 'use 2261640'
```

The new reference is `tools/parity/checkpoints/<name>.json`; an existing file
is not overwritten. It contains values, actions and SHA256 provenance for the
actual runtime, decoder and original save files, never proprietary game files.
Keep the raw original saves, patch manifest, screenshots and action notes in
local evidence storage. A change to an expected result requires new original
evidence; a remake failure alone is never a reason to change the oracle.

| Step | Execution |
| --- | --- |
| `talk <npc> <topic>` | Open the ordinary NPC topic list, select the topic and finish the conversation. |
| `use <object-id>` | Issue the ordinary use command and wait for the mechanism state to change. |
| `enter <zone>` | First step only; restore the before variables in the destination and include its entry script in the measured delta. This is a cheat entry, not a travel-route test. |
| `leave <exit-id> <zone>` | Teleport the party to the exit, require availability and the normal confirmation when applicable, then execute the normal transfer and verify the destination. Village exits follow their ordinary immediate departure. |
| `leave <exit-id> <zone> <entrance>` | Also open the ordinary destination panel on the travel map, require the recorded entrance to be offered, select its arrow and confirm. Verify both the loaded destination and arrival number. |
| `script <expression>` | Execute the same explicit original-console operation. State clearly when this bypasses physical interaction or combat. |
| `wait <seconds>` | Advance simulation for the recorded watcher delay, at most 300 seconds per step. |
| `reload` | Save and reload the remake before continuing; use for continuation checks whose original result is independently recorded. |

`--step` can be repeated. `--settle` controls initial fixture settling (default
2.2 seconds, or 20 for entry checkpoints); `--after-settle` defaults to 2 seconds.
Use `--script-transition` when a recorded dialogue or script intentionally
changes zones; the original after-save destination is still required to match.

An example fixture shape:

```json
{
  "money": 500,
  "quest_items": ["AmbushKey04"],
  "party_name": "Checkpoint",
  "party": [{"name": "Hero", "prototype": "Hero3"}],
  "world_time": 12.1,
  "setup": ["GodMode(0,1)"],
  "setup_steps": [{"wait": 2}, {"script": "SwitchLeverState(GetObject(1712),1)"}]
}
```

Only supply physical prerequisites that the original before save already has.
Never grant the fragment or set the completion flag whose outcome is being
tested. `setup` expressions and `setup_steps` run after map entry, before the
baseline check. For chapter transitions, `parties` maps archived party names to
member arrays, and `active_party` selects the initial party before map entry.
These can replace the single `party`/`party_name` fixture.

The native engine's active inventory and stored named-party inventory can
differ after console grants. If the tested script uses `AddLoot` or `CopyLoot`,
record the same inventory synchronization before both baselines, for example
a real same-zone transition. Do not infer the archived bag from `HaveItem`
alone. Likewise, use the native no-argument `RecalcMercBriefings()` when an
explicitly prepared roster needs its generic topics recalculated; supplying
an extra player argument does not execute that original command.

## Native observations and comparisons

The original console runs statements. Store a read-only expression in a unique
GS variable before **each** save, then declare it in `probes.json`:

```json
{"cp_fragment": "HaveItem(0,101)", "cp_torch": "GetLeverState(GetObject(2261640))"}
```

For example the console statement for the first probe is:

```
#0) GSSetVar(0,"cp_fragment",HaveItem(0,101)
```

The original closes the last parenthesis. Native zero-valued GS variables may
be omitted from saves; the recorder explicitly interprets the named probe as
zero. Probe variables are removed from the ordinary GS comparison and their
expressions run independently in the remake. Money is always observed.
Probes must be read-only, including every nested call; random draws and state
mutations are rejected. `money` is reserved for the independently decoded
native purse. An unknown explicit script operation also fails the replay.

The native recording helper can round-trip `cp_capture_nonce` to prove that
the console is accepting commands and a fresh save was read. Declare that
exact diagnostic with `--recording-only-var cp_capture_nonce`; the omission
is retained in `provenance.recording_only_vars`. No other `cp_*` variable is
silently excluded, and a diagnostic cannot also be a gameplay probe.

The report checks:

- Entry: the prepared remake state matches the original before variables and
  observations. Entry checkpoints omit this comparison because their before
  save is in another zone.
- Delta: exactly the same non-clock GS variables change to the same values.
- Observations: money, quest items, mechanism states and other declared native
  measurements match; a missing observation is a failure, even when zero.
- Destination, failed assertions, engine errors and complete output markers.
- Repeatability across fresh profiles, excluding clock/bookkeeping fields.

Only `gtime`, `zt.*` and `zs.*` are excluded. In particular **quest flags and
`z.<destination>` exit gates are compared**. Exit status is 0 for all matches,
1 for differences, and 2 for setup/capture errors. Runtime errors, duplicate
results and empty/partial captures cannot pass.

The legacy `sweep` subcommand still imports first-entry zone sweeps. Its older
schema has no new executable/probe provenance; it must not be described as a
patched-1.02 reference without a fresh recording. A previously visited native
zone includes persisted actor/lever state, so do not treat it as a fresh-entry
fixture without reconstructing and checking that state.

The [initial LiA qualification](validation/lia-kel-checkpoints-2026-10-23.md) and
[whole-campaign extension](validation/lia-campaign-checkpoints-2026-10-23.md)
list coverage, prepared checkpoint seams, passability repairs and remaining
differences.
