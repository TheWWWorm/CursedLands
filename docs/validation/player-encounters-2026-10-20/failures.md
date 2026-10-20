# Player-encounter failures — 2026-10-20

Production baseline: stable **1.19.0**, commit
`50fd5b06e7a17a6dea63fe85693f23c0485cfbb1`.
This audit changes tests and reporting, not production gameplay.

The remake results contain **two confirmed runtime defects and one unresolved
pause-timing failure**. The separate original comparison retains **five
probability differences in one behavior family**. These results do not establish
when any defect was introduced.

## 1. Loading-cover replacement followed by resize uses freed drawing resources

**Confirmed runtime defect.** `interface/loading_cover` prepares a fallback
cover without artwork, begins completion, replaces it, and resizes the viewport
before the previous node is deleted. The old resize callback calls
`LoadingScreen._draw_frame` with already-freed canvas handles.

The log records three `Parameter "canvas_item" is null` errors at
`game/src/ui/loading_screen.gd:345–347`.
`_remove` frees its rendering resources and queues node deletion without
disconnecting the viewport's `size_changed` callback. An earlier capture
encountered the same errors through the ordinary startup window resize; the
final fixture explicitly reproduces that ordering.

The runner stops this process on the diagnostic. Its `-9` exit is the runner's
termination, **not evidence of an engine crash**. A final assertion summary
was not reached. Rendering after that invalid-resource access is not qualified.

Evidence: [loading log](logs/loading-cover.log).
Reproduce with `--case interface/loading_cover --render-display :91`.

## 2. Malformed fresh-hero metadata causes a co-op validation error

**Confirmed runtime defect**, in both the base and Astral campaigns.
`coop/coop_fresh_start_guards` and its Astral variant send a numeric
`new_origin=1`, where the protocol requires a Boolean.
`CoopProgress._pristine_new_origin`, at
`game/src/game/coop_progress.gd:506`, evaluates `int != bool` and logs:

```text
Invalid operands 'int' and 'bool' in operator '!='.
```

The fixture reaches the error through direct validation and the receive path.
Its other 76/base and 75/Astral assertions pass, but runtime diagnostics make
both configurations errors. Normal fresh-hero joins and before-start joins
pass. This establishes faulty malformed-input handling; it does **not**
establish a normal join crash, successful unauthorized import, or exploit.

Evidence: [base log](logs/fresh-origin-base.log),
[Astral log](logs/fresh-origin-astral.log).
Reproduce both with `--case coop_fresh_start_guards`.

## 3. Arena menu pause does not immediately freeze the displayed combat clock

**Reproduced assertion failure; player impact remains unresolved.**
`arena/arena_round_lifecycle` fails `menu pauses combat at 2x` in all three
rounds in two captures under Xvfb/Mesa llvmpipe. The diagnostic rerun records:

| Round | First paused sample | Later paused sample | Advance |
|---|---:|---:|---:|
| 1 | 3.685 s | 3.740 s | 0.055 s |
| 2 | 3.025 s | 3.465 s | 0.440 s |
| 3 | 3.245 s | 3.410 s | 0.165 s |

The menu is open, the local phase remains paused, animation/environment
processing is disabled, and the worker clock command contains `paused=true`.
An additional two-second observation confirms that the clock subsequently
stops in every round. Closing the menu resumes it.

`ArenaPveMatch.apply_board` still assigns `world.time` from incoming worker
snapshots while preserving the local paused phase
(`game/src/game/arena_pve_match.gd:655–669`). The observations are consistent
with delayed snapshots, but do not yet distinguish expected transport
settlement from a visible pause defect on normal hardware. The original
prompt-pause assertion remains failing; it was not relaxed.

Evidence: [pause log](logs/arena-pause.log).
Reproduce with `--case arena/arena_round_lifecycle --render-display :91`.

## 4. Original comparison: unaimed hit probability is higher in five cases

**Measured original/remake difference, previously known and freshly
reconfirmed.** Of 430 bounded scenarios, 425 match and five differ. Each side
was captured twice with identical results. Each differing probability is
higher in the remake by `1/41`, approximately **2.44 percentage points**.

| Scenario | Original | Remake |
|---|---:|---:|
| `a41_d40_distance1` | 48.780488% | 51.219512% |
| `a41_d40_distance5` | 48.780488% | 51.219512% |
| `a40_d40_distance10` | 46.341463% | 48.780488% |
| `a41_d40_distance10` | 48.780488% | 51.219512% |
| `a20_d10_distance10` | 58.536585% | 60.975610% |

These use spread 40, target radius 0.5, and action speed 15.
Production comments describe omitted distance/weapon-speed terms in the
unaimed approximation, but this audit does not establish the exact root cause.
These are five cases in one behavior family, not five separate newly
introduced bugs.

Evidence: [full original comparison and boundary contracts](original-report.md).
The reference executable SHA-256 is
`d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8`.

## Test setup corrections excluded from the game-defect list

Earlier raw captures remain unchanged. The selected results use the latest
capture whose test dependencies and campaign match the current catalog.

- Corrected campaign assignments for base-only Nalo, camera/party/permissions
  and actor-tombstone fixtures, and the Astral touch-picking fixture.
- Supplied real Astral recruitment data, required travel titles and co-op
  package configuration. Added explicit Astral quest-text coverage.
- Repaired synthetic actor/session setup, navigation occupancy after test
  teleports, a warning-as-error type annotation, and completion summaries.
- Made the reconnect fixture capture the actual final progress package when
  normal Exit destroys the session. Reading it before Exit caused a
  save-selection race. The final 155-check tests pass in both campaigns.
  Dependent network fixtures were rerun after that helper changed.
- Used actual schema-4 family IDs and an explicit saved-opening fixture.
  Disk-save comparisons normalize integer fields because JSON reads them as
  floats and Godot dictionary equality distinguishes their Variant types.
- Corrected an Arena composition fixture to contain the three Beast families
  its assertion requires; retained the behavioral assertion.
- Ran loading progress with a real renderer and its required movie.
  Recreated option panels per language and waited for the startup display
  transition before screenshots. Remake translations are exercised in EN/RU/DE;
  original archive labels still come from the installed English edition.

These setup corrections do not constitute production fixes. No failure was
waived. The three remake findings above leave four configurations nonpassing,
because the fresh-origin defect has two campaign configurations.

For complete per-configuration results see [report.md](report.md); for checked
features and explicit gaps see [features.md](features.md).
