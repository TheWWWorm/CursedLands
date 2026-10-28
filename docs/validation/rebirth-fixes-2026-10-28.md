# Rebirth edition fixes — 28 October 2026

The Rebirth edition of the original game patches a number of original bugs.
These were checked against Cursed Lands, which follows the original. Six apply
to the remake and are fixed here on branch `fix/rebirth-audit-fixes`, which is
based on local main `8c54bfa5`. Original addresses are in the GOG English
`game.exe` 1.06 (SHA-256 `d0fc0bb2…660ad8`).

Every fix has a new regression test. Each test fails against the unfixed code
and passes with the fix. All runs are headless with
`tools/parity/gameplay.py`, using the base campaign and the original
Lost in Astral data.

| Fix | Original behaviour | Evidence | Test (unfixed → fixed) |
| --- | --- | --- | --- |
| Destruction and Astral Rift quick cast | Quick cast (a double click on the spell icon, or belt use) aims a spell at the nearest enemy only if its prototype type is in the offensive list (types 0–8, 17, 19, 25, 30, 32, 34, 36, 38). Destruction (40) and Astral Rift (41) are damage spells, so they hit the caster. | Observed under Wine 11.20 in gz11k with a hostile white tiger adjacent. Destruction hit the hero for 295 and Astral Rift for 347; the tiger stayed at 90 HP. The Fire Arrow control went at the tiger. Belt use was not run under Wine; the decompile indicates the same path. | `commands/damage_spell_quick_cast` and `commands/damage_spell_quick_cast_astral`: 7 failures each → 22/22 |
| Lost in Astral loading movies | The base executable maps Gipat to `progres2`, Ingos to `progres3` and Suslanger to `progres4`, and plays `progres1` for gz1g and bz7g. Lost in Astral's own executable (`0x4EA40B`) also maps Gipat2 to `progres2` and Jigran to `progres5`. The remake used the base mapping, so Gipat2 and Jigran zones showed `progres.bik`. | Static, from the two executables' mapping code. | `interface/loading_movies_astral`: 65 failures → 243/243. Base `interface/loading_movies`: 161/161 both before and after. |
| Negative Use value opens skill locks | The lock check (`0x522A80`) compares the lock level with the Use value (Dex − 25 + Use) unsigned. A character with Dex below 25 and no Use skill has a negative value, which opens every skill lock. Now the comparison is signed, as in Rebirth. A level 0 lock still opens for anyone, and quest keys are unchanged. | Static (disassembly). Not observed under Wine: no reliable script method lowers Dex. | `quests/lever_skill_sign` and `_astral`: 11 failures each → 27/27 |
| Antimagic starts battle music | The combat-state test (`0x54B580`) treats a cast as fighting when the spell type is below 9 or is `0x1A`. Type `0x1A` is Antimagic, as the spell prototype table of both campaigns confirms. Antimagic is no longer counted. | Static (disassembly and data). | `commands/antimagic_battle_music` and `_astral`: 2 failures each → 48/48 |
| Effects freeze on sleeping units | The update loop (`0x58D670`) skips frozen objects in campaign "game" zones, so their timed effects stop counting down until the party comes near. Now a frozen unit's effects count down once a tick. When one runs out, the unit is woken (as `0x58D5D0` does) and its update removes the effect. That happens on the same tick as it would on an awake unit. | Static (disassembly). The active-set behaviour itself was traced under Wine earlier (see `docs/ai_activity.md`). | `effects/sleeping_effects`: 6 failures → 16/16 |
| Disassembly ignores wear | For weapons and armour, the camp price (`0x60FA70`) computes every deal as price × coef[mode] − price × coef[8] × wear (`FSUB` at `0x60FB4E`). So a worn item cost less to take apart and rebuild than to repair. The remake charged a flat price × coef[7]. Now the disassembly fee adds the repair cost, as Rebirth does. Selling and the other deals keep the original subtraction. | Static (disassembly). | `inventory/disassembly_wear` and `_astral`: 72 failures each → 99/99 |

## Not changed

- **Native crash guards** (moving, adding and removing map objects, and creating unknown items): the remake has no native crash path to guard. `Items.info` returns an empty record for an unknown id.
- **Effect recast and the 20-effect cap:** the remake keys effects by name, so a recast replaces the old effect. This is not an overflow, and recast rules are a separate design question.
- **Wake countdown of idle units:** the original arms 128 + ((object address >> 5) & 15) ticks. The remake uses 128 + ((uid × 7) & 15): the same range of 7.0–7.9 s, chosen deterministically. Per unit the two differ by at most 15 ticks, which is within the original's own variation from run to run. The comparison tooling never relies on repeated original runs, and the original seeds its gameplay random generator from the clock, so heap layout is not a gap.

## Related regressions

Final source, headless, with the base campaign and Lost in Astral data:

- **57 related programs:** quick cast, direct commands, spell selection, self-cast, belt, combat state, stealth, effects, levers, camp, market, shop, loading and arena. 56 pass. `arena/arena_live_shop` fails 16 arena-save checks, and it fails the same 16 on unmodified `8c54bfa5`, so the failure predates these changes.
- **85 programs:** every headless base and Lost in Astral campaign flow, plus `creatures/object_activity` (24 checks) and `creatures/object_activity_absence` (6). All pass.
- **Unregistered lever tests:** `lever_use_flags` passes 240/240 in each campaign. `locked_hover` passes 26/26 with Lost in Astral data; it uses a Lost in Astral zone, so it errors on the base campaign.

`object_activity.gd` and `object_activity_absence.gd` now print a runner marker and are registered in the gameplay catalog, so the active-set behaviour that the frozen-effects fix touches is covered by the runner.

## Combined with the nearby-unit order fix

`fix/notice-candidate-order` merged cleanly (`f0f65faf`). A combined headless run covered 179 programs: the related set above, all campaign flows, perception, registry, AI activity and every arena program. 174 passed.

- **Four existing arena failures:** `arena_economy`, `arena_elimination_places`, `arena_live_shop` and `arena_result_health`. Each fails identically on unmodified `8c54bfa5`.
- **`arena_tournament`:** this one did not fail on main. With the merged changes, the fights went differently and the human company survived past round 30. From round 31 every tournament save was rejected on reload. The cause predates these changes: with live boards, a CPU company's result recorded the tournament round instead of the company's own round, which stays within the expedition's 30 rounds. On reload the CPU company is checked against that limit. `arena/arena_late_round_save` reproduces this deterministically: 9 failures before the fix, 100/100 after. All 32 arena programs were rerun with the fix: `arena_tournament` passes 199/199, and the other four failures are unchanged.
- **Original-code comparison:** `run.py --case perception_` gives 469 match, 2 differ (the known group D). The 177 parity unit tests pass.
