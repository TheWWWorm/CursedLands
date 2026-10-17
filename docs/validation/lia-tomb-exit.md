# Lost in Astral tomb exit, 17 October 2026

Issue: [#16](https://github.com/TheWWWorm/CursedLands/issues/16).
Baseline: published `v1.10.0`, with the patch based on
`2da3e23cee9fbb542b318a0d1637b383a3909e68`.

## Reproduction and cause

The original `zone11dun1.mob` contains both The Magic Needle and Hall of the
Great. Completing the needle sets `q.gz11d1.q16ag=2` and `z.gz11g=0`, opening
the return exit to the Rift. Later island travel reveals the Rift again,
setting `z.gz11g=1`. That value also closes the tomb's direct exit.

The tomb's original `Start` routine reopens the exit when its water mechanism
is already activated. The remake preserves the region's script machine, where
that first-visit routine has finished. Returning for Hall of the Great therefore
leaves the exit closed, including after saving and loading.

`tools/tests/lia_tomb_exit.gd` reproduces this with the original map and script:
activate the needle's mechanisms and chest, return to the Rift, reveal its
island-map region, revisit the saved tomb, and open the Hall's reward chest.
The released build fails eight recovery/exit assertions in the final test.

## Repair

On restoration of this particular Lost in Astral region, rearm the original
startup only when the needle is completed, the water lever is activated, the
first startup has finished, and the return exit is closed. Verify the complete
original startup and needle-completion definitions, plus their startup call,
before doing so. A modified script is left alone.

The original startup retains its 20-tick wait and water/particle restoration.
Already running or suspended startups are not duplicated. Quest completion and
reward routines are not replayed. No save format, game asset, player text,
option, network protocol or release version changes.

## Validation

Tests used isolated profiles and a Linux pack exported from the changed game
source, running on the previously qualified production engine. Original game
archives were supplied separately; none are bundled in this patch.

| Check | Result |
| --- | --- |
| Tomb quest progression, revisit, recovery, save during the recovery wait, repeated recovery, mod/campaign/stage exclusions, and real exit confirmation/travel | 36 assertions passed |
| Load a blocked checkpoint written by the unmodified released build, save/reload it again, and return to the Rift | 10 assertions passed |
| Existing Lost in Astral Revenge revisit regression | 13 assertions passed |
| Existing original-campaign elder-departure regression | 6 assertions passed |
| Rendered exit and confirmation, Russian at 1024×768 | 9 assertions passed |
| Rendered exit and original English/German confirmation text at 1024×768 | 10 assertions passed per language |
| Translation scanner | 2,472 entries, 141 dynamic wiki keys, 123 dynamic arena keys; zero errors |

All 94 assertions passed. Rendered checks verify the open exit particles,
interaction label, localized confirmation layout and confirmation-button travel.
The English/German UI checks load the original confirmation strings from their
respective base-game text archives; the tomb retains its Russian Lost in Astral
map and story data. This is a focused confirmation-layout check, not a claim of
full expansion localization.

Run the functional regression using the project's normal `--tool` entry point:

```sh
CursedLands.x86_64 --headless --render-thread safe --audio-driver Dummy -- \
  --no-local-worker --ei-path=/path/to/LostInAstral \
  --tool=/path/to/checkout/tools/tests/lia_tomb_exit.gd
```

It writes `tomb-blocked.sav` inside its isolated profile. Use
`--save-fixture=/absolute/path/to/tomb-blocked.sav` to check a checkpoint from the
baseline build. For rendered checks, use `lia_tomb_exit_ui.gd`, omit `--headless`,
and optionally pass `--ui-texts=/path/to/english-or-german/res/texts.res`.

The reporter did not attach a save. Recovery was verified against reproduced
checkpoints from the released build. Mechanisms are activated directly in the
regression, so this does not claim a complete walking/combat playthrough or
co-op/Windows/macOS/Android/Web runtime coverage. No release was published.
