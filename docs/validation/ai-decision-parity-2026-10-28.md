# AI decision parity fixes — 28 October 2026

An audit compared the remake's AI and unit-order decisions with the original
`game.exe` (GOG English 1.06, SHA-256 `d0fc0bb2…660ad8`). It found fourteen
differences, A1–A14. Twelve are fixed on branch `fix/ai-decision-parity`, which is
based on local main `374c2d3c`. A14 is a deliberate remake behaviour and is
recorded below. Addresses refer to that executable.

Every fix has a new regression test in the gameplay catalog. Each test fails
against the unfixed code and passes with the fix. All runs are headless with
`tools/parity/gameplay.py`, using the base campaign and the original Lost in
Astral data.

## Fixes

| # | Original behaviour | Remake before | Test: unfixed → fixed |
| --- | --- | --- | --- |
| A1 | A unit under a script `Follow` keeps running its motivations (`5d2580` takes no account of the AI state), so it leaves the follow to attack a hostile it notices. | The scripted follow skipped the AI, so a follower walked past enemies. | `creatures/scripted_follow_engage`: 3 of 10 fail → 10/10 |
| A2 | When a unit is attacked, its hostility spreads to friends within the help radius that notice it. A friend that takes it claims it for 30 ticks and passes it on, so it travels along a group (`553da9`, hostility tick). | Only a remake rule: units that saw the assault turned hostile at once. Chains did not form. | `creatures/hostility_spread`: 2 of 14 fail → 14/14 |
| A3 | Each charm stage needs power above stage × 10 + the creature's tame value (`551ae0`), not level × 10. A failure on a creature the tamer's side had begun taming undoes it (`552280`) and counts as an attack (`455680`). Any attempt on a unit a player owns fails. The charm repeats until the target has the caster's player (`6818aa`). | The level was compared, failures had no effect, and owned units could be charmed. | `creatures/charm_taming`: 12 of 17 fail → 17/17 |
| A4 | An aim at a part that is no longer intact is dropped when the order is given (`554b30`) and after the blow that breaks it (`549ec0`). Later blows land on random parts. | Blows kept aiming at the broken or severed part, so they did no harm. | `combat/aimed_broken_part`: 3 of 7 fail → 7/7 |
| A5 | A blow is not dealt when the target has left the reach planned at the start of the strike (`549d40`, `54ca40`): reach + 0.5 m, plus half the way a moving target in front can go before the impact. A caster that can no longer cast loses the spell. | Every started blow landed, and a feebleminded caster still released its spell. | `combat/strike_reach_cancel`: 2 of 6 fail → 6/6 |
| A6 | A party unit's attack or cast order on a unit goes on only while the target is of its side or player, noticed by the unit (`5cb7f0`), or in the player's group (`66e0d0`). That group is the union of all party units' noticed lists (`66e0f0`). Otherwise the order ends with "no target", ack 0x12 (`54dd70`). | Party orders chased a target nobody perceived for ever. | `combat/party_target_lost`: 1 of 7 fail → 7/7 |
| A7 | Feeblemind sets the can't-cast flag except on weapon type 16 (`553220`): bats, evil eyes, dragons and curses whose attacks are spells keep attacking. | Feeblemind disabled those creatures entirely. | `combat/feeblemind_spell_creatures`: 2 of 6 fail → 6/6 |
| A8 | Every blow or shot that is not a backstab makes a noise of twice the attacker's hearing detectability for 26 ticks (`54f450`). Hostile units in hearing range that do not see the fight become suspicious of the spot. | Fights made no noise. | `combat/attack_noise`: 2 of 4 fail → 4/4 |
| A9 | The UMFollow motivation only enters the Follow state when no AI action is under way (`5d1e10`). That state (`5d6f90`) stops within FollowMinDist 2 m, sets off only when the target is more than FollowMaxDist 4 m from the follower's goal, leads a walking target by its position 5 ticks ahead and steps aside when it walks into the follower. | A one-off walk to the target's current spot whenever it was more than 3 m away. No lead and no sidestep. The remake already had the original Follow state for script `Follow` and the F order; UMFollow now uses it. | `creatures/umfollow_escort`: 3 of 8 fail → 8/8 |
| A10 | Switching to an alarm's descriptor (`5d6630`) rebuilds the whole motivation list from it, including those a script set, and clears the AI target and state. | Script-set motivations, the AI target and the AI state survived the alarm. | `creatures/alarm_behaviour` (shared with A11): 5 of 13 fail → 13/13 |
| A11 | The descriptor's always-active flag is taken from the current descriptor (`5d6bee`), and the switch wakes an always-active unit (`5d6c3c` → `58d5d0`). The active-set expiry (`58d8ce`) and load arming (`596b9e`) read that current flag. | Only descriptor 0's flag was read, and an alarm woke nobody. zone7letter's runner (descriptor 1 always active) could freeze on his way to the shaman. | `creatures/alarm_behaviour` |
| A12 | An attack on a living flyer at altitude 1.5 or more is refused with ack 0xc unless a bow or crossbow is in hand (`554b30`). A running order on one ends (`54d960`), and the AI's reach test leaves it out (`54c800`). The remake keeps no height above the ground, so the original's relative height term is 0. | Melee units walked under high flyers and hit them. | `combat/high_flyer_refusal`: 2 of 10 fail → 10/10 |
| A13 | No hit reaction plays for a unit standing in an attack whose next strike is due before the reaction would end (`549d00`). Being hit never delays its blows. | A reaction could hold up the next strike. | `combat/hit_reaction_tempo`: 1 of 4 fail → 4/4 |

### Approximations and open points

- **A2:** the original's per-unit observer list is approximated by the remake's nearby-unit list (`_notice_candidates`). The hostility itself also reaches the victim at once on the hit, as in the original.
- **A3:** releasing a player's earlier pet when a new one is tamed (one pet per player) is not changed. It is not yet confirmed whether a carried pet keeps its taming stage across zones.
- **A5:** the original adds the attacker's turn ticks to the impact time. The remake's strike starts already facing the target, so there are none.
- **A6:** the remake's noticed lists come from its own perception. Where that differs from the original, so will the moment an order ends.
- **A9:** the persistent follow order is the same code the script `Follow` and the F order use. That code was compared with `5d6f90` earlier and matches.

## Not changed

**A14 — a cast short of stamina waits.** In the original, an ordered cast that is short of stamina once the target is in reach fails with "can't cast" (ack 0xf; 0x11 for a belt item) and the order ends (`54d960`, check at `54bf80`). The remake acknowledges "can't cast" once and then waits in place until stamina has regenerated, then casts. A new order cancels the wait. This is a deliberate remake convenience and is covered by `spells/spell_stamina_wait`.

## Older tests changed

These tests asserted remake-only behaviour that the fixes replace. The new assertions follow the original rule; nothing was loosened.

- `creatures/creature_alerts`: a rabbit near an attacked friend is not hostile at once. It turns hostile once the claim period has passed (31 AI ticks).
- `creatures/patrol_escape_alerts`: the witness section now checks the original spread (help radius, noticed by the friend) instead of the removed "saw the assault" rule.
- `persistence/save_taming` (`save_depth.gd`): it checked that a failed charm keeps a reloaded partial taming. It now checks that the failure undoes it, as in the original. The completed stage-2 taming after reload is still checked.
- `combat/archer_range`, `animation/direct_moving_casts`, `pathing/attack_path_current_target` and `animation/killing_posture_queue`: these switch perception off and order attacks or casts on a target the party never perceived. They now give the attacker the noticed entry that A6 requires. Everything else they check is unchanged.

## Original game under Wine

All checks used the original GOG English executable under Wine 11.20, in GPU Lab, with god mode on and audio off. Values were read with console probes, and body-part states from decoded quicksaves. Voice acknowledgements could not be heard, so they are inferred.

| # | Result | What was seen |
| --- | --- | --- |
| A1 | Confirmed | gz13k: a bodyguard under a script `Follow` left its idle target to attack the hero (6–10 m from the followed unit). |
| A2 | Confirmed (chain) | gz13k: after one citizen was attacked, its friends turned hostile one by one over about 9 s, up to 17 m away, with delays of the claim scale. Whether a friend facing away takes part was not isolated. |
| A3 | Not tested | The base game has no way for a player to charm: no item or unit carries the spell, and a script spell container gives no cast slot. |
| A4 | Confirmed | gz3g: about eight aimed blows all hit an orc's right leg. Once it broke, later blows hit the arm, the other leg and the torso, and the orc died. The same happened with a brigand's left arm. An order aimed at an already broken part was not tested, because a broken part recovers within seconds. |
| A5 | Inconclusive | Feeblemind timing against a quick cast could not separate a cancel during the cast from a refusal at its start. Melee reach was not tried; console moves are too coarse for one swing. |
| A6 | Confirmed | gz3g, hero sight 13 m: with a live attack order, the hero chased an orc moved 6 or 9 m away. Moved 13.4 m or more, out of both the hero's noticed list and the player's group, it stopped at once. |
| A7 | Confirmed | gz3g: a type-16 bat kept hitting the hero for about 11 under repeated Feeblemind. Feeblemind did stop the hero's own healing. |
| A8 | Not tested | Suspicion from noise is not visible through the console. |
| A9 | Confirmed | gz7g, the z7q1 script sequence on a neutral orc: it stopped 1.93–1.96 m from the hero. It did not set off with the hero placed 3.3 or 3.9 m away, but did at 4.2 and 4.6 m, measured from where it stood. When the hero walked into it, it stepped about 1.3 m aside. The 5-tick lead (about 0.3 m) is too small for 1 Hz sampling. |
| A10 | Not tested | The motivation list cannot be read from the console. |
| A11 | Confirmed (main point) | gz7g with Zone7Letter: after alarm 1 the party was moved about 330 m away. The runner (descriptor 1 always active) walked about 149 m to within 10 m of the alarm point while a descriptor-0 companion stayed frozen. He set off only after about 28 s and did not reach the shaman. |
| A12 | Confirmed | gz19h: a dagger hero clicked on a blue dragon (altitude 7) did not move. A ground click moved it. |
| A13 | Not tested | Needs frame-exact timing of reactions against the attack cooldown. |

## Related regressions

Headless, with the base campaign and Lost in Astral data. Each failure listed as a baseline fails with the same checks on unmodified `374c2d3c`.

- **403 programs** (every category, at the A1–A7 and A12 state): 387 passed. The four A6 fixture cases (see "Older tests changed") were found here. The rest are baselines:
  - four arena programs (`arena_economy`, `arena_elimination_places`, `arena_live_shop`, `arena_result_health`);
  - `pathing/path_preview`;
  - `commands/worker_travel_clock` (zone 3 data missing);
  - `inventory/recruited_equipment_net_astral`;
  - `dialogue/gipat_captive_dialogue_hermit_first`;
  - four co-op checkpoint programs (`coop_solo_return`, `coop_vm_solo`, `coop_guest_roles_net`, `coop_guest_roles_net_astral`).
- **293 programs** (quests, combat, creatures, stealth, commands, spells, animation, party, dialogue, persistence, pathing; all fixes): 287 passed. Failures:
  - `pathing/attack_path_current_target` and `animation/killing_posture_queue`: they ordered attacks on targets the party had not noticed, and now give the attacker that entry (see above).
  - `quests/campaign_clock_coop_astral` timed out under load. It passes on the final commit.
  - The rest are the baselines above.
- **117 programs** on the final commit (arena, co-op, network, inventory, progression and the three programs above): the three pass, and the only failures are the baselines above.

The twelve new tests run together: all fail on `374c2d3c` (between 1 and 12 failed checks each) and all pass on the final commit.
