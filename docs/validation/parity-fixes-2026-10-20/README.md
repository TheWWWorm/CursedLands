# Original parity fixes and expansion — 20 October 2026

**All 3,511 original-versus-remake scenarios match**, with two identical
captures per side. All **72 previously reported failures are resolved**.
The expanded suite adds **1,111 comparisons**, including 261 additional
authored condition lists.

| Reference | Scenarios | Matching | Differing | Observations per capture | Authored lists | Maps represented |
|---|---:|---:|---:|---:|---:|---:|
| Base game | 2,221 | 2,221 | 0 | 12,271 | 983 | 69 |
| Lost in Astral | 1,290 | 1,290 | 0 | 9,221 | 738 | 120 |
| Total | 3,511 | 3,511 | 0 | 21,492 | 1,721 | — |

Every previous scenario is still present. Its original observation hash is
unchanged, including all 72 cases that previously differed. The fixes change
the remake; no comparison tolerance was widened and no failing case was removed.

The [failure disposition](failures.md) lists each resolved case and its
earlier differing field/value. [All scenario results](scenario-results.json)
include passing cases and observation hashes. The
[validation receipt](validation.json) records the executable identities,
source/capture hashes, contracts, repeated-run qualification, source audit and
local reproduction paths.

## Causes fixed

- **Quest numeric values:** literals, variables and each nested numeric result
  are consumed as float32. Equality compares those values exactly, so nearby
  unequal values cannot prematurely satisfy a condition. Remake object-identity
  comparisons remain supported. ASCII string equality preserves case.
- **Direct rectangle checks:** both bounds are inclusive, degenerate rectangles
  can contain their exact point, and reversed corners stay reversed.
- **Quest areas:** native rectangle constructors and circle constructors are
  now compared too. Rectangles retain their four corners without a float32
  size/end round trip. Circle containment uses a float32 squared radius, double
  precision distance arithmetic and a strict boundary. Triggers, area objectives
  and guard-area checks share the same containment path.
- **Distances:** missing/freed actors use the original float32 `1e30` sentinel.
  Coordinate differences and squared sums retain double precision until the
  final float32 result. Translated coordinate tests exposed an extra rounding
  step that origin-only fixtures did not detect.
- **Group constants:** native `Every` returns a non-call numeric condition
  directly; `Any` converts it to a boolean. These cases do not iterate, even
  with an empty group. Nested conditions retain their group iteration.
- **Healing and maximum HP:** the float32 healing argument is checked against
  the original double `0.001` cutoff. Distribution factors, per-part health,
  rescale factors/ratios and final aggregate HP use the native operation order
  and storage boundaries. No-op healing cannot reactivate a disabled part.

The new comparisons exposed 101 additional failing scenario/reference pairs
during development; all now match. This count combines repeated fixtures and
the same causes in two executables, not 101 distinct player bugs.

## Additional coverage

The native quest adapters now execute `GroupSize`, `GroupHas`, `Any`, `Every`,
`IsInArea`, and the rectangle/circle construction helpers in both executables.
Cases cover empty/single/mixed/dead groups, membership order, short-circuiting,
iterator reuse in later conditions, fractional corners, reversed and empty
areas, circle edges, signed/zero radii, area unions and missing IDs.
Area containers are preallocated; actor reference release is supplied while
native assignment, iteration, construction, lookup and predicates run.

Numeric cases now observe arithmetic cancellation results and distances at
translated positions, for both actor-to-point and actor-to-actor queries.
The base body suite adds 48 varied six-part bodies, each with 16 mixed
heal/rescale operations. Sizes, lethalities, states and damage vary; negative
heals and both sides of the tiny-heal cutoff are included.

Authored condition lists retain their original expression trees and order.
Actors, flags, group membership and area geometry are controlled inputs.
They do **not** replay map initialization, quest rewards, script scheduling
or complete campaign playthroughs. The new area geometry is a shared fixture,
not a claim about the area active at a particular point in a real save.

## Verification and compatibility

All **79 Python harness tests pass**. New controls cover iterator binding,
dynamic group/area rejection and valid group/area sampling.

The selected headless gameplay regressions finish with **54 passing
configurations and 84,360 checks**: 28 quest, 11 effect, 11 persistence and
four combat configurations. These are remake regressions, separate from the
original-executable results above. [Gameplay results](gameplay-results.json)
retain each test's source, log hash, profile and capture path.

The initial full run passed 53 configurations and reported one fixture error:
Shelter departure closed its ENet peers while world processing could still
emit combat RPCs. The fixture now disables its manually driven world's frame
clock and stops processing before closing peers. It passed two fresh reruns.
The aggregate uses the latest result for each configuration; the initial error
remains recorded. Production sources match all qualified native captures and
gameplay runs; only this test fixture changed after the full regression run.

An isolated game copy changed circle containment from `<` to `<=`.
`quest_predicate/area_circle_4` failed against Astral's original executable in
both captures. The working game stayed unchanged, and exactly one source file
differed in that private copy.

The parser/save integration test exercises numeric literals and assigned
results, old `Rect2` save records, new rectangle-corner serialization,
objective/guard containment and freed actors. Old area records remain readable;
new rectangles preserve the original corners exactly. Geometry already
normalized or rounded in an older save cannot be reconstructed from that
record alone.

Earlier compile/type-inference errors and an incomplete integration-test
fixture are retained as diagnostics, not passing evidence. The fixture now
supplies its `Session`. The health-cache regression compares cached HP with a
forced fresh evaluation; numerical HP expectations are covered independently
by original-executable comparisons instead of the previous double-only formula.

No player-visible text was added. All runs use private profiles with a free
cursor, FPS displayed and all audio muted. The source changes do not publish
a release or modify an existing tag.

## Reproduction and limits

Follow [the comparison runner setup](../../original-parity.md), then run each
campaign with `--authored-quests --quest-limit 0 --repeat 2`.
The qualified base and Astral runs both exit `0`. Each retained capture
directory has a `reproduce.sh` that accepts a new output directory and an
optional `--case` filter.

The gameplay selection uses `tools/parity/gameplay.py` with both installation
paths, `--category quests --category combat --category effects --category
persistence --display headless`. The fixture reruns use
`--case quests/shelter_departure --display headless`. Use a new `--out`
directory for every run; preserve the initial diagnostic reports.

The original hashes remain:

- Base: `d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8`
- Astral: `f04a305b77c84ea29c18ad2996d23072ccef1c0c46876c9b93bae4ce9351d1ff`

Native captures use pinned Unicorn 2.1.4 with x87 control word `0x027f`.
Static Ghidra evidence and executed-instruction captures are recorded
separately. No original binary bytes or asset contents are committed.
Missing coverage still includes full quest-thread lifecycles, inventory
predicates, dynamic group/object construction, complete movement/combat
sequences, Astral body/effect routines, rendering and full campaign completion.
