# Quest, Astral and body parity — 20 October 2026

This is the retained pre-fix result. The
[subsequent fix report](../parity-fixes-2026-10-20/README.md) resolves all 72
differences and adds further comparisons; the original receipts below remain unchanged.

**2,400 original-versus-remake scenarios ran, with two identical captures per
side: 2,328 matched and 72 differed.** This adds 1,806 comparisons to the
previous 594-scenario base-game suite. All 594 existing scenarios still match.
There were no setup, incomplete-capture or repeatability failures in the
qualified runs.

| Reference | Scenarios | Match | Differ | Observations per capture |
|---|---:|---:|---:|---:|
| Base game | 1,714 | 1,661 | 53 | 10,047 |
| Lost in Astral | 686 | 667 | 19 | 4,683 |
| Total | 2,400 | 2,328 | 72 | 14,730 |

The [complete failure list](failures.md) gives every failing scenario, first
step/field and original/remake values. [Scenario results](scenario-results.json)
retain passing cases too; the [validation receipt](validation.json) records
binary identities, source and output hashes, contracts, original MOB hashes,
coverage gaps and local paths to full captures.

## Quest triggers and Lost in Astral

The suite now executes the original expression evaluator and ordered
condition-list dispatcher. The remake side calls production `ScriptVM._eval`
and `ScriptVM._run`. Observations include condition order, short-circuiting,
whether the body dispatches, and cumulative dispatch count.

The new inputs cover quest flags, hash-bucket collisions and missing keys,
lever states, HP/death checks, missing actors, distances, numeric/string
comparisons, nested expressions, entering/leaving/re-entering rectangles and
multiple conditions. Separate adapters pin Astral's own executable addresses;
the remake process verifies that it loaded the expected campaign.

All **1,460 supported authored condition lists** extracted from the installed
MOBs were included, beyond the initial 120-list sample per campaign:

| Installed scripts | Condition lists | Match | Differ | Maps represented |
|---|---:|---:|---:|---:|
| Base | 925 | 913 | 12 | 67 |
| Astral | 535 | 535 | 0 | 118 |

The twelve authored differences are `zone2.mob` / `VCheck#0#88` and
`zone19.mob` / `VCheck#0#115`–`#122`, `#279`, `#295`, `#300`, all block zero.
They reject their upper rectangle corner in the remake while the original
dispatches the trigger. For example, the `zone2` condition includes
`(62, 155)` in the original rectangle `(49, 142)`–`(62, 155)`.

These tests supply actors and campaign state to the preserved condition
trees. They establish condition behavior under those inputs, not whether a
particular quest is blocked during ordinary play. Astral's 535 matching lists
do not establish full campaign parity. Unsupported whole lists remain recorded
as gaps, including inventory queries, group quantifiers, area registries,
world-time queries and dynamic object/string bindings.

## Unresolved differences

Counts below group failing scenarios by their first difference; repeated
fixtures and the same behavior in two executables are not separate player bugs.

| Behavior | Base cases | Astral cases | Observed difference |
|---|---:|---:|---|
| Numeric equality | 4 | 4 | Nearby unequal float32 values compare equal in the remake; one prepared trigger dispatches early |
| Nested arithmetic | 2 | 2 | Original stores intermediate results as float32; remake intermediates can change a later predicate |
| String equality | 2 | 2 | Original ASCII comparison is case-sensitive; remake lowercases both strings |
| Rectangle conditions | 18 | 6 | Original includes upper edges; remake excludes them. Reversed/degenerate rectangles also differ. Includes the twelve authored base triggers |
| Distance rounding | 2 | 2 | One float32 bit differs in the tested fractional-coordinate distance |
| Missing-actor distance | 3 | 3 | Original returns approximately `1e30`; remake returns `99999`, which can satisfy a large-distance threshold |
| Zero/tiny healing | 10 | 0 | Original ignores healing magnitudes at or below `0.001`; remake can change HP or a disabled part's state |
| Body arithmetic precision | 12 | 0 | Healing/rescaling leaves small float32 differences in HP or part HP |

The ordinary binary-exact rescaling sequence matches. All **20 effect-lifetime
scenarios** match, including signed-counter wrap, expiration and dead actors.
Quest flag and lever comparisons also match in the tested single-player,
player-zero fixtures. Some body cases intentionally use unusual prepared part
states; their reachability and player-visible impact are not established.

No gameplay fix or tolerance exemption was introduced in this change. The
differences remain failing comparisons.

## Harness qualification and corrections

All **74 harness tests pass**. New negative controls reject cross-campaign
addresses, unsupported Astral families, unknown binaries, incomplete traces,
missing/reordered condition observations, invalid effect observations and
unsupported/ambiguous authored script inputs.

An isolated game copy changed `IsLess` from `<` to `<=`. The previously matching
`quest_predicate/IsLess_0` then returned true against the original false in both
captures. Exactly one production-source file differed in that private copy.
The working game's source was unchanged.

An earlier diagnostic HP adapter rewrote an immediate argument inside code
already translated by Unicorn. This left a stale maximum-HP argument after
rescaling and produced misleading large differences. The wrapper now has
immutable instructions and reads its argument from data memory. The final
full base run was captured twice after this correction. Its output replaces
the diagnostic for qualification; raw diagnostic files were not overwritten.

Captures use pinned Unicorn 2.1.4 and x87 control word `0x027f`, private game and
native-harness snapshots, and isolated profiles with free cursor, FPS enabled
and all audio muted. Original binary hashes are checked before executing any
address. No native executable bytes or original asset contents are committed.

## Reproduction

See [the runner documentation](../../original-parity.md) for setup.

```sh
.venv-parity/bin/python tools/parity/run.py \
  --game-dir /path/to/base-game --godot /path/to/godot \
  --authored-quests --quest-limit 0 --repeat 2 --out /tmp/parity-base-new

.venv-parity/bin/python tools/parity/run.py \
  --campaign lost_in_astral --game-dir /path/to/astral --godot /path/to/godot \
  --authored-quests --quest-limit 0 --repeat 2 --out /tmp/parity-astral-new
```

Both qualified runs exit `1` because documented differences remain. Exit `2`
means setup/capture failure and must not be counted as a game mismatch.
Each private result folder includes a `reproduce.sh` accepting a new output
directory and optional `--case` filter.

The remaining gaps include full quest-thread scheduling and one-shot disposal,
quest rewards/inventory, save/load continuity, Astral body/effect routines,
complete original playthroughs and rendering. These bounded comparisons do not
replace those forms of validation.
