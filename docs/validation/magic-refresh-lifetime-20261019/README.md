# Refreshable spell visual endings

Local validation on 19 October 2026, starting from `17f38a25`. This addresses a
specific within-world lifetime defect. It does not establish the cause of the
larger reported restart-sensitive FPS loss. The earlier full Trials sessions,
deep co-op traversal and same-save restart comparisons remain in
[the campaign validation](../campaign-controls-presence-20261019/README.md) and
[the allocation investigation](../session-retention-isolation-20261019/README.md).

## Finding

`Spells._buff` replaces the current effect of the same type on its target.
`ParticleFx.magic_fx`, however, previously allocated a separate ending timer
for every Weakness, Strength or Lichdom event. Refreshing an effect left old
deadlines active, and target death did not release those timers. Expiry could
create the ending burst on a corpse still present in the world.

The focused regression reproduced 256 live timers after 256 same-power
refreshes of each effect. It also observed an obsolete ending deadline firing
after a refresh and an ending burst on a dead carrier. Ten of the initial
46 assertions failed against the unchanged production code. This deliberately
accelerated lifecycle test is not an FPS or normal-play benchmark.

REA/Ghidra checked the original base executable's complete function body
`0x510b80`–`0x5111c4`. Its visual effect list matches active type/power before
creating a new start burst, and removes unmatched visual entries. The cases
for Strength/Weakness and Lichdom use the corresponding signed start/end
bursts. The relevant static evidence, executable hash, analysis profile,
assembly, pseudocode and limitations are in `native-effect-list.json`, evidence
`ev_258571c877109a8f3973520892fbc18e9770823ef269352eec213c660b76a064`.
This is static evidence, not a recording of the original executable running.
It does not establish equivalence of all original buff stacking/stat rules.

## Change and regression coverage

The renderer now retains one refreshable timer per carrier instance and effect
code. A same-power refresh restarts that timer without another start burst.
A power change replaces the visible burst and updates its eventual ending.
Dead, detached or transferred carriers release their pending endings on the
next particle tick; the expiry callback independently checks the carrier too.
Clairvoyance's point-bound ending remains independent.

All 57 final assertions pass in both the stock editor runtime and the corrected
exported runtime. The same refresh exercise retains `[1, 1, 1]`
timers instead of `[256, 256, 256]`. Coverage includes independent carriers and
effect types, power changes, refreshed deadlines, death, detachment, removed
carriers, replay without a starting burst, zero-duration deferral, 1×/2×,
pause/resume, arena settlement, and repeated world teardown with long-lived
magic endings. The raw before/after logs are retained alongside this file.

No player-visible strings, spell stats, mana costs, duration rules, original
assets, quality settings or published version metadata were changed.

## Rendered follow-up

`tools/benchmarks/coop_traversal_session.gd` records delayed-effect timers,
active magic endings, spell-light counts, resources and static allocation in
addition to its existing movement/combat/frame samples. The follow-up uses
the corrected exported build, two rendered clients and a separate local
authority. It uses Ultra, 2×, 1920×1080, equipped level-15 heroes and the
authored `gz17h` map with live enemies and scripts. Movement and combat use
normal game commands; the diagnostic does not teleport during play, delete
enemies, disable incoming damage or replenish mana. Both clients share the
same RTX 3090, which limits comparison with two separate player machines.

Both clients completed seven wall-clock minutes (approximately fourteen
simulated minutes). Each had a 30-second baseline before beginning movement.
The party reached the fortified area and continued fighting there.

| Observation | Owner | Guest |
| --- | ---: | ---: |
| Travelled distance | 427 m | 442 m |
| Maximum distance from entrance | 248 m | 248 m |
| Newly dead authored creatures, shared world | 28 | 28 |
| Observed own cast-action serials | 45 | 44 |
| Final hero health | 745 | 762 |
| Sampled active magic endings | 0–1 | 0–1 |
| FPS range over complete 2× intervals | 71.6–114.7 | 76.1–115.1 |

The shared-world kill count is not additive across clients. Cast serials count
observed cast actions, not guaranteed hits; the raw records distinguish command
attempts. Both characters survived with incoming damage enabled. No script or
engine errors were logged. `owner-060.png`, `owner-300.png` and `owner-360.png`
show the route and later encounters. The raw log, per-client samples, source
and executable hashes, and computed results are included in `summary.json`.

The guest's final sample arrived as owner teardown reset its clock to 1×; it
is excluded from the 2× FPS interval range. The release runtime reports zero
for `Performance.MEMORY_STATIC`: those raw zero fields mean unavailable heap
accounting, not zero allocation. The engine's resource monitor remained 492,
but that monitor alone does not establish absence of resource or driver leaks.

Moving-camera samples cannot be used as a matched before/after performance
comparison. The 90-to-30 FPS decline remains unreproduced. This follow-up
validates normal movement/combat with the lifetime fix, not a general cure for
the reported slowdown.
