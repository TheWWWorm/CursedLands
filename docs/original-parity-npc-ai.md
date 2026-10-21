# Original parity: NPC AI decisions (`npc_ai_*`)

This extension family compares the NPC AI's own decisions with the original
executable. It covers the Fear priority, suspicion and help calls, the option
and target score, and motivation arbitration. Script commands (UM*, Guard,
alarm, diplomacy) and perception-driven noticed-list maintenance belong to
other families and are not repeated here.

Files:

- `tools/parity/cases_ext_npc_ai.py`: inputs, contracts and validators. It
  contains no expected values and no Python model of any formula.
- `tools/parity/native_ext_npc_ai.py`: original captures under Unicorn.
- `tools/parity/remake_ext_npc_ai.gd`: remake captures, which call the
  production `UnitAI` methods through fixture subclasses.
- `tools/parity/test_ext_npc_ai.py`: input-shape, validator and mismatch
  tests. It also has an optional native determinism test, which runs when
  `PARITY_GAME_EXE` is set.

Run the family with:

```
python run.py --game-dir <owned game> --out <new dir> --case npc_ai_
```

Only the original campaign is qualified. Lost in Astral addresses are not
declared, so `contracts("lost_in_astral")` is empty.

## Kinds

| Kind | Original entry | Remake entry | Observation per step |
|---|---|---|---|
| `npc_ai_fear` | `5d53b0..5d547d` prologue, Fear priority `5d2960`, suspicion `5cbbe0`, hit hook `5d7e90` | `_fear_priority`, `suspect`, `on_attacked` | priority, flee radius r and spread j (f32 bits), kept danger point, perception level/delta/point |
| `npc_ai_suspicion` | `5cbbe0`, help call `5d5990` (grid query `5c0bd0`, friend table `0x7c2bb4`, delayed sound `5cbba0`/`5ccd40`), `5d7e90`, perception tick `5cb700`/`5cc9d0` per unit | `suspect`, `call_for_help`, `hit_hook`, `tick`, `_susp_level` | per living non-party unit: level, delta, point bits, delayed-sound counters |
| `npc_ai_target_score` | score `5cf9a0` with `522ae0`, `524020`, `50f630` and `5cfe20`, stored to f32 as its caller `5d0030` does | `_score` | f32 bits of the score |
| `npc_ai_motivation` | AI tick `5d53b0` up to the AI-state switch (`5d56de`): real priorities of the logic-model-3 motivation sets, current +100, strict-greater choice in list order, leave/enter/tick dispatch, attacker reset | `think` | the motivation whose body ran (`calm`, `suspection`, `fear`, `none`) |

### Motivation sets

The motivation sets follow the original constructor, with Sentry first as the
calm motivation for logic model 3:

| Aggression mode | Motivations, in order |
|---|---|
| 0 | Sentry, Aggression, Suspection, CorpseWatcher, Fear(0) |
| 2 | Sentry, CorpseWatcher, Fear(0) |
| 3 | Sentry, CorpseWatcher, Fear(1) |

Motivation vtables:

| Motivation | Vtable |
|---|---|
| Sentry | `0x73d190` |
| Suspection | `0x73d1f8` |
| Aggression | `0x73d260` |
| CorpseWatcher | `0x73d294` |
| Fear | `0x73ff8c` |

Slot `+0x10` is the priority, `+0x14` the tick, `+0x18` enter, `+0x1c` leave
and `+0x20` the type.

### Native layout used

**Unit:**

| Offset | Field |
|---|---|
| `+0x1c` | position |
| `+0x17e` / `+0x180` | HP and maximum (shorts) |
| `+0x198` / `+0x19c` | effect array (20-byte entries, id in the low byte) |
| `+0x240` | controller |
| `+0x244` | hostility mask |
| `+0x24c` | party flag |
| `+0x250` | side |
| `+0x324` | movement class |
| `+0x460` | spell slot 0 |

**Controller:**

| Offset | Field |
|---|---|
| `+0x164` | creature state |
| `+0x190` / `+0x1b4` | current / posted command |
| `+0x1e0` | body (parts at `+0x110 + 0xf4·i`) |
| `+0x238` | legs wound factor |
| `+0x8e6` | armour shorts |
| `+0xa4c` | option power |
| `+0x980` | AI record |

**AI record:**

| Offset | Field |
|---|---|
| `+0x2c` | target |
| `+0x30` | attacker (one AI tick) |
| `+0x38` | help radius |
| `+0x74` | motivation list |
| `+0x8c` | current motivation |
| `+0xd0` | perception |
| `+0x114` | noticed list |
| `+0x18c` | noticed-hostile flag |

**Perception record:**

| Offset | Field |
|---|---|
| `+0x10` | point |
| `+0x18` | level |
| `+0x1c` | delta |
| `+0xa8` | delayed sounds (0x18 bytes each, counter at `+0xc`) |

**Option record:**

| Offset | Field |
|---|---|
| `+0` | type |
| `+8` | range |
| `+0xc` | targets − 1 |
| `+0x10` | radius |
| `+0x14` | duration or effect id |
| `+0x1a` | damage shorts |

**ai.reg block:** `0x7c53e8`.

## Mappings between native codes and remake values

**Suspicion and fear state**

- Perception level/delta (int) ↔ `meta suspect` `_susp_level` / `d`.
- Point (f32 x, y) ↔ `suspect.pos`.
- Fear record r/j/danger (sentinel `0xc4a42000`) ↔ `meta fear` r/j/danger.

**Motivation**

- AI+0x8c pointing at a Fear/Suspection/Sentry record ↔ `_fear_tick` /
  `_investigate` true / `_sentry` having run.
- Fear current ↔ `meta fear_on`.
- Walking (controller+0x190 == 1) ↔ an order of type `move`; the Fear walk
  is `fear: true`.
- Aggression current ↔ an AI attack order.

**Units and diplomacy**

- Noticed party unit ↔ the remake's life-sense detectability.
- Friend table bit ↔ `world.relation == 0`.
- Party flag ↔ `controller >= 0`.

**Score inputs**

- Effect id n ↔ buff key `effect<n>`.
- Damage/armour shorts ↔ `opt.v` / `stats.armor`.
- Option power ↔ `options(c).power`.

## Event timing protocol

Each step is one world tick.

- **Original side:** "before" events, then each observed unit's AI tick (or
  the routine under test), then the observation, then "after" events.
- **Remake side:** the clock advances (`time += 55 ms`, as `GameWorld._tick_body`
  does), then "before" events, the observation or decision, "after" events,
  and finally `UnitAI.tick()` (delayed help sounds, which run after every
  unit).

What the two event kinds mean:

- **"before":** something earlier in the same world tick, such as an
  attacker that ticked first.
- **"after":** something later in that tick.

## Declared boundaries (stubs)

**Every kind**

- CRT allocation and free.
- CString and debug-log streams.
- The unit dead/type virtual getters.
- Reference release is a no-op.

**`npc_ai_fear`, `npc_ai_suspicion` and `npc_ai_motivation`**

- The perception scan `5caa00` adds nothing. The noticed list is an input, and
  the remake `player_perceive` is cached for the tick.
- The help-call query uses one 16 m unit-grid cell that holds every fixture
  unit.

**`npc_ai_fear` and `npc_ai_motivation`**

- Ranged-weapon predicate `54b6c0`.
- Danger-cell test `5bbdb0`, by exact point (remake `danger_at` override).
- Legs wound factor (remake `wound_factor(3)` override).
- ai.reg values: RangedAttackDist 7, RangedRunDist 4 and DamageLevelRunLimit
  0.5, as shipped.

**`npc_ai_fear` only**

- The remake `world.nav` is empty, so a kiting spot search finds no path.

**`npc_ai_suspicion` only**

- The help radius is written to AI+0x38 directly. The shipped
  CallForHelpRadius and CallForHelpRadiusDefault (7/7) make the remake mapping
  the identity.

**`npc_ai_target_score` only**

- HP records are supplied (remake `_get_hp` override).
- Option power is supplied (remake `options` override).
- Every candidate has controller+0x164 = 1 and an empty remake path.

**`npc_ai_motivation` only**

- The tick, enter and leave entries are recorder stubs. On the remake side
  `_fear_tick`, `_susp_go` and `_sentry` are recorder overrides, and
  `calm_tick` returns false.
- The AI-state switch after the motivation tick is not executed.

## Limits

These areas are not covered:

**Noticed hostiles in arbitration and kiting**

- Arbitration with a noticed living hostile (Aggression 10000, Fear 3000 and
  15000 with spot search) needs the option choice `5d0030` and path search.
- Kiting is covered only while walking or out of range.

**Fixed inputs**

- The corpse queue is empty, so CorpseWatcher always returns −1000.
- Type 3's NO_SCORE branch (candidate controller+0x164 == 0) is not compared.
  The field is a creature state, and how it maps to the remake's "walking a
  path" test is not established.

**Not in this family**

- The choice ordering, area safety and reachability in `5d0030`.
- Party or dead units as help-call friends.
- Sounds other than help calls.
- The ai.reg parser `5ce0f0`, which was not added.

## Results (run `npc-ai-07`)

Run `results/npc-ai-07` gives 98 matches and 84 differences, with exit code 1
(harness OK). The run uses seed 20261020 and fuzz 12.

| Kind | Match | Differ |
|---|---|---|
| fear | 67 | 21 |
| suspicion | 5 | 31 |
| target_score | 3 | 16 |
| motivation | 23 | 16 |

### Divergence classes

Each scenario is listed under the class that explains its first divergence.

**Behaviour: motivation arbitration**

| Class | What happens | Scenarios |
|---|---|---|
| M1 | Fear does not hold. The original keeps a current Fear at priority level/6 + 100 while the level is above 50; the remake drops Fear once its priority is 150 or less (level ≤ 905). | `motivation/fear_hold_mode2_level1000`, `fear_hold_mode3_level1000`, `fear_hold_far_point` (step 4: expected `fear`, got `calm`); `motivation/seeded_000`, `003`, `005`, `009`, `010` (expected `fear`, got `calm`) |
| M2 | Danger against a current Suspection. The original needs 350 > M + 100; the remake needs 350 > M. | `motivation/danger_vs_suspection_m250`, `m251`, `m260`, `m300`, `m349`, `fear_then_suspection_level300` (step 2: expected `suspection`, got `fear`) |
| M3 | After Fear ends, the original picks Suspection only if M > 50 (it is no longer current). The remake resumes an "active" Suspection down to M ≥ −50. | `motivation/fear_then_suspection_level240` (step 38: expected `calm`, got `suspection`) |
| M4 | A new suspicion at the same point. The original keeps the Suspection minimum M (5d1e90 compares the point); the remake resets m to the new level. | `motivation/same_point_resuspect` (step 21: expected `fear`, got `suspection`) |

**Behaviour: Fear priority**

| Class | What happens | Scenarios |
|---|---|---|
| F1 | The radius test for the level/6 branch (Fear not current: the unit within r of the suspicion point) adds the observer's own z² (`dx² + dy² + z² < r²`); the remake uses a 2D distance. | `fear/flag1_party_noticed_d9.9` (expected −1000, got 166); `fear/suspicion_point_height_12.0` (step 1: expected −1000, got 149) |
| F2 | The Fear(1) party range is strict `<` in the original; the remake's `live_units_near` uses ≤. | `fear/flag1_party_noticed_d10.0` (delta: expected 0, got −2) |
| F3 | The Fear(1) party pick: the original takes the nearest noticed party unit, the remake the first in registry order. | `fear/flag1_two_party_order` (point x: expected 7.0, got 12.0) |
| F4 | The kiting target: the original takes the nearest noticed hostile by 3D distance, the remake by 2D. | `fear/kite_nearest_3d_versus_2d` (expected 3000, got 15000) |
| F5 | Kiting while walking: the original returns 15000 for any walk command (code 1); the remake does so only for its Fear walk and otherwise searches a spot (no path in the fixture). | `fear/kite_other_walk` (expected 15000, got 3000) |
| F6 | Flee-radius growth uses the 3D attacker distance × 1.5 in the original; the remake uses 2D. | `fear/hit_hostile_fighting`, `hit_hostile_far_not_fighting`, `hit_hostile_far_height` (r: 15.0187 vs 14.8492, 21.3322 vs 21.2132, 18.75 vs 15.0) |
| F7 | Hit suspicion while fearful. The original Fear priority always suspects the attacker (1000/−2); the remake `on_attacked` returns early when fearful. | `fear/hit_hostile_fighting_fear` (delta: expected −2, got 0); `hit_after_decision_fear` (step 1) |
| F8 | A friendly attacker: the original Fear and Suspection priorities still suspect it; the remake skips relation 0. | `fear/hit_ally_fighting` (expected 166, got −1000) |
| F9 | Timing of hit suspicion. The original suspects in the next AI tick's priority; the remake suspects at once in `on_attacked`, so it shows one tick of decay. | `fear/hit_after_decision_calm` (step 1: expected 1000, got 998); `fear/seeded_002`, `seeded_008` (expected 1000, got 998) |

**Behaviour: help calls**

| Class | What happens | Scenarios |
|---|---|---|
| H1 | The help radius is strict `<` in the original grid query; the remake's `live_units_near` uses ≤. | `suspicion/help_radius_7_d7`, `help_radius_10_d10` (step 1 pending: expected `[]`, got `[25]`) |
| H2 | Ordering of the delayed sounds. The original counts them down in each unit's own AI tick; the remake counts them in `UnitAI.tick()` after every unit, so a call earlier in the tick than the friend's decision is seen one tick later. It also no longer replaces an entry from the previous tick. | `suspicion/help_before_decision` (step 0: expected 25, got 26); `seeded_000`, `003`, `005`, `006`, `009` (25 vs 26); `seeded_001` (pending length 1 vs 2) |

**Precision and clock**

- **J — suspicion clock.** `_susp_level` counts `floor((time − t0) / 55 ms)` on
  the accumulated double clock (`time += 0.055`). For about half of all
  (t0, time) pairs this loses a tick (for example ticks 26→27). The original
  adds delta once per AI tick.
  - Level expected 897, got 900, the tick after a delayed sound converts:
    `suspicion/help_radius_7_d6.9`, `help_radius_10_d9.99`,
    `help_radius_height`, `help_friend_filter`, `help_after_decision`,
    `help_over_level_899`, `help_twice_same_tick`, `help_twice_next_tick`,
    `help_two_callers_one_friend`, `help_friend_leaves`, `hit_by_hostile`,
    `hit_by_party`, `hit_by_nothing`.
  - `suspicion/suspect_equal_rejected` (497 vs 499), `suspect_below_zero`
    (−6 vs −5), `decay_long` (946 vs 948).
  - `suspicion/seeded_002`, `004`, `007`, `008`, `010`, `011` (level one
    delta high).
  - `fear/radius_decay_after_hit` (157 vs 158), `fear/seeded_003` (49 vs 50),
    `seeded_004` (9 vs 10), `seeded_010` (798 vs 800), `seeded_011`
    (149 vs 150).
  - `fear/seeded_006`: a lost tick lets an equal-level suspicion be rejected,
    so the point differs.
- **P — float32 storage in the score.** The original uses the f32 constant
  1.3f (1.29999995) and stores the pre-penalty score and the distance as f32.
  The remake uses double 1.3 and a Vector2 (f32) distance. The results differ
  by 1 to 7 ulp.
  - `target_score/bolt_damage_sweep` (step 5: −29.1000023 vs −29.1000004),
    `area_lasting` (step 2: −46.800003 vs −46.799999).
  - `target_score/seeded_000` through `seeded_011` (one f32 ulp up to 7 ulp,
    for example `seeded_004` type 7: −356.09268 vs −356.09247).
- **A — area radius edge.** The original compares the exact squared distance
  with the f32-rounded r²; the remake compares an f32-rounded squared distance
  with the exact r². A member exactly at r is therefore counted on opposite
  sides whenever r² is not representable.
  - `target_score/area_radius_edge` (step 0, r = 0.7: expected −105.6, got
    −69.9). All seven radii disagree.
- **W — 16-bit damage wrap.** `522ae0` takes each damage − armour as a 16-bit
  difference and drops it when bit 15 is set. With negative armour the
  remake's `maxi(0, v − a)` keeps 32777.
  - `target_score/damage_edges` (step 2: 108067.5 vs 216233.6).

## Mutation proof (run `npc-ai-08-mutant`)

`--game-source` pointed at a scratch copy of `game/` with four one-line edits
to `ai.gd`. The edits are saved in `results/npc-ai-08-mutant/mutation.diff`;
the copy itself was deleted afterwards.

- Fear spread: j eases with `+3.01` instead of `+3.0`.
- Weapon score `+1.0`.
- Suspection activates at `> 149` instead of `> 150`.
- Help delay of 25 ticks instead of 26.

The mutant gave 27 matches and 155 differences. Every edit is detected:

- All 67 matching fear cases flip, first at `j_bits`.
- `target_score/weapon_basic` flips at step 0.
- `motivation/suspection_start_level150` flips at step 1.
- `suspicion/help_over_level_900` and `help_over_level_950` flip at
  `pending[0]`.

No mismatching case matched under the mutant.
