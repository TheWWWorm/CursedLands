# Original-engine comparison qualification — 2026-10-20

The new comparison runner captured **126 scenarios and 788 observations per
side** against Cursed Lands 1.19.0 source at
`50fd5b06e7a17a6dea63fe85693f23c0485cfbb1`. Both sides were captured twice in
fresh processes and produced identical repeated observations.

**121 scenarios match; five differ.** The full run exits `1`, as required for
captured behavioral differences. These five cases belong to one combat
probability discrepancy; they are not five independently established bugs.

The [per-scenario results](scenario-results.json) contain all 126 outcomes and
trace hashes. The [validation record](validation.json) retains the failing
inputs, both sides' observations, source/tool hashes and mutation control.
See the [runner documentation](../../original-parity.md) for reproduction.

## Captured differences

All rows use an unaimed attack, random spread 40, target use radius 0.5, and
equal supplied action-speed values of 15. The native result enumerates all 41
roll residues with equal weight.

| Attack / defence | Distance | Original | Remake |
|---|---:|---:|---:|
| 41 / 40 | 1 | 48.780488% | 51.219512% |
| 41 / 40 | 5 | 48.780488% | 51.219512% |
| 40 / 40 | 10 | 46.341463% | 48.780488% |
| 41 / 40 | 10 | 48.780488% | 51.219512% |
| 20 / 10 | 10 | 58.536585% | 60.975610% |

The first differing field is `$.steps[0].state.probability` in each case.
The difference is one of the 41 supplied roll outcomes, or approximately
2.439 percentage points. This is consistent with the distance and action-speed
terms that `game/src/game/combat.gd` already documents as omitted. No gameplay
change or mismatch exemption was introduced.

## Validation of the runner

- All **26 harness tests passed**, including first-field reporting, exact bit
  comparisons, missing/duplicate/truncated capture rejection, target-selection
  termination, input/reference fingerprints, altered-tolerance rejection and
  protection against recursive source copies or overwritten results.
- In an isolated game copy, the target-selection comparison was changed from
  `d < best` to `d <= best`. The native selection order remained `2, 0, 1`; the
  mutated remake selected `1, 0, 2`. Both repeated captures agreed, and the
  runner exited `1` at the first observation.
- The generated `reproduce.sh` replayed that same target-ordering scenario
  against the unmodified source. Both repetitions matched and it exited `0`.
- The final strict Godot import and all capture logs were free of script/runtime
  errors. Initial clean-import bootstrap diagnostics are retained separately.
- The original executable hash and all 1,074 copied production source files
  were checked after the runs and remained unchanged.

An earlier seeded terrain fixture supplied two different elevations for the
same XY coordinate. That cannot be represented by the supplied ground lookup
and produced a false target-ordering difference. The generator now uses unique
XY positions; replay validation explicitly rejects ambiguous heights. A
regression test covers that constraint. The five differences above come from
the corrected final run.

## Reference and scope

- Original: GOG English base `game.exe`, SHA-256
  `d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8`,
  no additional patches.
- Native execution: Unicorn 2.1.4, explicitly supplied x87 control word
  `0x027f`, with boundaries declared in `cases.py`.
- Remake: Godot 4.7 stable, Python 3.12.3 orchestration, Linux.
- Every remake process used a fresh profile: cursor free, FPS enabled, all
  game audio muted.

This qualification covers the seven documented subsystem families. It does
not establish campaign, save/load, navigation, complete AI, multiplayer or
renderer equivalence. Capturing whole-game random draw order also remains
outside the current suite.
