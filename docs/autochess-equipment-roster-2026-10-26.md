# Autochess equipment, rank statistics and Horde roster

Equipment targets remain reachable in a full nine-creature formation. The
layout searches beyond the six original nearby positions, avoids interactive
HUD panels, and draws a line to displaced targets. Empty reserve containers
allow field clicks through. Targets stay still during item selection despite
idle head animation; camera, viewport, HUD and formation changes recompute them.

Alliance badges support clicking to keep the roster open, wheel scrolling from
the badge or the roster, and Escape to dismiss it. The inspector uses the height
beside the commander portrait. All sixteen installed Beast families are reachable.

The creature inspector shows one-, two- and three-star values with the current
rank in bold. Comparisons include the same item and deployed alliances; the
current rank uses the live actor, including combat effects. Wounded creatures
show remaining health separately. Field health labels contain the current value
without repeating maximum HP. Damaging spells appear as `Spells: Lightning
(40/72/160)`, with the current value bold; amounts are before armor, per hit or
per pulse as indicated. Buff/healing spell names remain labeled as spells.
Russian attack statistics use the noun `Атака`. EN, RU and DE are covered.

## Recruit and balance decisions

- Orc archer: three gold, Horde/Hunter, original `OrcFemaleA3/A5/A7` bow forms.
  Their original 101-tick draw cadence remains intact. This supplies a heavier
  ranged Horde option between the existing cheap shooters and expensive units.
  Three portraits were rendered from the original models. Base recruitment now
  has 30 families; the installed expansion has 38. Family 29 remains retired.
- Banshee health factor: 1.10 → 0.98. Spell and attack budgets remain unchanged.
  Repeated mirrored team comparisons found the original opening and middle
  ranks too broadly successful. The health change retains the lightning role.
- Jun lizard attack factor: 0.78 → 0.86. A health increase was rejected after it
  failed to restore the existing frontline contribution guardrail. The modest
  damage increase restores useful team contribution while retaining counters.

Save schema 17 appends family 38 without renumbering previous families. Schema
16 saves retain their identities and equipment. Arena protocol 5 requires peers
to agree on the changed roster. Campaign prototypes are unchanged.

## Evidence and limits

The baseline roster scan contains 4,428 native fights: every same-price pair,
three star ranks, duel/frontline/ranged-support contexts, two seeds and both
orientations. The expanded scan contains 4,716 fights. Jun matchups were rechecked
in all three contexts and ranks with four seeds (432 fights); only these rows
change in the final matched comparison because support selection uses base-game
families and never includes Jun lizards.

| Family | Before, team points at stars 1/2/3 | Final matched team points |
| --- | --- | --- |
| Banshee | 82.3% / 81.3% / 66.7% | 69.8% / 62.5% / 56.3% |
| Jun lizard | 32.3% / 26.0% / 37.5% | 32.3% / 51.0% / 52.1% |
| Orc archer | New recruit | 48.4% / 60.9% / 59.4% |

These are diagnostic scripted lineups, with draws worth half a point, not human
match win rates. Full nine-player tournaments also exercise recruitment, item
allocation, formations, elimination and late-game compositions. The retained
raw results permit further balancing without treating these few policies as a
complete competitive metagame.

The registered equipment regression uses a legal compact formation and real
click/drag input. Restoring the old target logic makes two Woodsfolk targets
unreachable and prevents their Swift Boots assignments. Restoring the old
alliance interaction makes the roster disappear while moving from its badge.
Restoring the old Banshee health fails the team-balance guardrail at two ranks.

Autochess inventory assignment, alliance panels and star budgets have no
counterpart in the original campaign, so an original Wine interaction comparison
is inapplicable. Native prototype inspection confirmed the Orc archer's bow,
empty spell list and cadence. Native spell parsing and real unarmored hits
validate displayed spell damage; this is remake regression evidence, not a claim
of original-executable Autochess parity.

Older adjacent tests were also run on unchanged local main. Their failures
predated this change: alliance bonuses already appeared during preparation;
optional recruits required mounted data; the HUD used a 1440×900 logical canvas;
reserve slots fitted their shelf; formation arrivals delayed the combat start;
and ordinary victories used a banner instead of a blocking dialog. The fixtures
now assert those accepted behaviors, retaining native combat, migration,
visibility and immutability checks. Balance thresholds were not weakened.

See [machine-readable validation](validation/autochess-equipment-roster-2026-10-26.json).
Rendered checks use GPU Lab auto allocation with isolated muted profiles and
free cursors. The exact stock-engine virtual-monitor refresh diagnostic is
retained separately from game/script failures. Source changes are local; this
work does not publish a build.
