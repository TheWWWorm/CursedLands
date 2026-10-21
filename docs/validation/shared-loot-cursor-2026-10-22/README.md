# Shared loot messages and cursor diagnostics

Local source changes on `feature/autochess-rank-variants-20261021`, following
`d00041da` and based on published 1.22.0. Status: committed source for review;
publication is outside this change.

## Shared loot

Pickup and shared-copy notices now use `Items.log_stacks` for their localized
item descriptions. Eight identical thin-leather units produce one `x8`
description for both the finder and the other recipient. Explicit stack counts
combine with individual copies. Different item identities, including wear,
charge and enchantment state, retain separate descriptions and the first-seen
order. Existing finder/party wording and money formatting remain in use.

The previous copy formatter described every inventory entry separately. The
unchanged baseline reproduces four formatting failures in the expanded pickup
fixture. Its three notification-related source files match the parent commit
byte-for-byte. The corrected fixture passes all 13 checks in EN/RU/DE, including
the actual HUD event path and a real corpse pickup. The network fixture checks
eight thin-leather units with either peer as the finder, actual emitted copy
messages and both inventories, plus the existing repeated-packet and corpse
interaction cases.

Native message windows:
[English](shared-loot-en.png), [Russian](shared-loot-ru.png),
[German](shared-loot-de.png). The full pickup and copy descriptions fit their
native text window at 1280 by 800.

## Cursor command

- `cursor`: print the current pointer position once.
- `cursor on`: sample continuously with a default 0.1-second interval.
- `cursor on 0.5`: choose an interval from 0.05 to 10 seconds.
- `cursor off`: stop sampling and disable polling.

Coordinates are pixels from the top-left of the game viewport, with X to the
right and Y downward. Samples include application uptime. They enter retained
console output and the desktop game log with a `[cursor]` prefix. `log cursor.txt`
exports the retained console output. Local diagnostics work before unlocking,
without a campaign, and while the console is closed or the campaign is paused.
They use real time; a delayed frame produces one sample rather than a burst.
Hidden sampling updates the bounded output buffer, and reopening redraws it.

Help, completion and status/sample text are supplied in EN/RU/DE. Rendered checks
move the actual pointer to (123, 234) and (456, 345), verify recorded coordinates,
and inspect the console in all three languages, including a narrow German
layout. Samples were also verified in the desktop `godot.log` file.

Console previews:
[English](console-cursor-en.png), [Russian](console-cursor-ru.png),
[German](console-cursor-de.png). See the [command guide](../../console.md).

## Validation

The [report](report.json) records exact commands, source hashes, isolated
profiles, retained raw logs and the baseline comparison. Twelve successful runs
contain **383 checks**:

- Pickup messages in EN/RU/DE: 13 per language.
- Shared inventory grants and actual ENet pickup traffic: 28 and 51.
- Cursor diagnostics: 27 headless and 30 rendered.
- Existing modern console and command/authority regressions: 67 and 126.
- Native shared-loot message windows: 5 per language.

All final runs completed with zero script/engine errors. Translation coverage is
3,018 entries with zero errors; all four added English keys have RU/DE entries.
`git diff --check` passes. New fixtures are registered in the gameplay catalog.

Every test used an isolated profile with `confine_mouse=0`, `show_fps=1`, all
three audio volumes zero, and the Dummy audio driver. These values were verified
in all twelve saved profiles. Rendered checks used a private Xvfb display and
OpenGL Compatibility/Mesa llvmpipe on Linux; these results establish behavior
and layout on this setup, not hardware performance measurements.
