# Quest checkpoints from original saves

`tools/parity/checkpoints.py` compares whole quest steps with the original
game. A checkpoint is two saves of the original made in the same zone, one
before and one after a single player action (for example an F5 quicksave
before and after a conversation), plus that action. The remake starts from the
original's "before" state, performs the action and must end with the same
script variables as the original's "after" save.

This complements the [original-engine comparison suite](original-parity.md),
which checks bounded routines instruction by instruction. Checkpoints check
the result of a quest step as a whole: which conditions fired, which
conversation and quest variables changed and to what.

## Reading original saves

`tools/parity/original_save.py` reads a save slot (`saves\saveq`,
`saves\savea`, ...). It unpacks the files with the original executable's own
decoder, run in Unicorn, and verifies each file's checksum. From the slot it
reports the zone, the party's heroes and money, and the GS variables, both as
the zone was entered (`scenario.sav`) and live (`mission.sav`). Lost in Astral
saves use the same format.

```sh
.venv-parity/bin/python tools/parity/original_save.py \
  --game-exe /path/to/EvilIslands/game.exe /path/to/EvilIslands/saves/saveq
```

The item containers and the unit stats block are read but not interpreted yet.

## Record a checkpoint

1. In the original, enter the zone and set up the situation. Quicksave (F5)
   immediately before the action and copy `saves\saveq` aside as the
   "before" slot. A save from earlier, such as the zone-entry autosave, also
   captures whatever the zone's scripts did since; it is not a clean "before".
2. Perform one action. Quicksave again and copy the slot as "after". Close the
   console first: with the console open, F5 goes to the console and nothing is
   saved.
3. Record it:

```sh
.venv-parity/bin/python tools/parity/checkpoints.py make \
  --game-exe /path/to/EvilIslands/game.exe \
  --before /path/to/before --after /path/to/after \
  --name bz2g_airy_estera --note "Airy: About Estera" \
  --step "talk daughter b.daughter.z0_3"
```

The checkpoint is written to `tools/parity/checkpoints/<name>.json`. It holds
only variable names and values, never game files.

Supported steps:

| Step | Meaning |
| --- | --- |
| `talk <npc> <topic var>` | Click the NPC, pick the topic, skip the walk with Space and play the conversation to its end. |
| `use <id>` | Order the first hero to use the lever, switch, chest or door with this map object id (the id the zone's scripts use) and wait until it is used. |
| `enter <zone>` | Enter the zone (the original's `LeaveToZone`). Must be the first step; later steps then start from the zone as entered, which is how to record a sequence such as a lever puzzle from a clean state; the "before" save is in the previous zone and the entry check is skipped, since the delta then includes the zone's entry. |

### Zone-entry sweeps

`checkpoints.py sweep <dir>` records one `enter` checkpoint per folder of a
sweep (`NN_<zone>/before`, `NN_<zone>/after`): a quicksave, the console's
`LeaveToZone`, about 20 s in the zone (arrival conversations played through)
and a second quicksave. A zone the original has visited before is restored
from its save and runs the original's absence simulation, while the remake
enters it fresh, so an entry checkpoint is exact only for a first visit.

### Probing the original's state

The console runs statements, not expressions, and closes the last
parenthesis itself. To read a value, store it in a GS variable and quicksave:

```
#0) GSSetVar(0,"dbgalive4501",Not(IsDead(GetObject(4501)))
```

`original_save.py` then shows `dbgalive4501` in the live variables. A
variable set to 0 is not written to the save, so store a value that is 1 for
the answer of interest.

## Run the checkpoints

```sh
.venv-parity/bin/python tools/parity/checkpoints.py run \
  --game-dir /path/to/EvilIslands [--astral-dir /path/to/LostInAstral] \
  [--name airy] [--out report.json] [--keep]
```

Each checkpoint runs `tools/tests/original_checkpoint.gd` in an isolated
profile. The run checks two things:

- **entry**: after entering the zone with the "before" variables, the remake's
  variables equal the original's "before" save;
- **delta**: the action changes exactly the variables the original's action
  changed, to the same values.

Clock and zone-bookkeeping variables (`gtime`, `zt.*`, `zs.*`, which the
original engine writes when a zone is left) are excluded. Exit status: 0 all match,
1 differences, 2 setup or run errors. `--keep` keeps each run's profile and
log.
