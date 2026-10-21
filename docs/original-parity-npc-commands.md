# NPC behaviour commands: original versus remake

Family `npc_commands` (`tools/parity/cases_ext_npc_commands.py`,
`native_ext_npc_commands.py`, `remake_ext_npc_commands.gd`,
`test_ext_npc_commands.py`) compares what quest-script commands do to an NPC's
AI record, the diplomacy matrix and the world alarm table. It is part of the
[original-engine comparison suite](original-parity.md) and runs against
the qualified base executable (`d0fc0bb2…`) and Lost in Astral (`f04a305b…`,
`--campaign lost_in_astral`); all three kinds are qualified for both.

```sh
V=/path/to/venv/bin/python
$V tools/parity/run.py --game-dir /path/to/original --godot /path/to/godot \
  --out /tmp/parity-npc --case npc_
# Lost in Astral: add --campaign lost_in_astral and its game directory.
```

## Kinds and observations

| Kind | Inputs | Observation after every step |
|---|---|---|
| `npc_motivation` | units (actor 0, target 1, dead unit 2), optional `.mob` logic descriptor, sentinel `[Logic]` values, command list | per observed unit: `present`, `blocked`, `side`, sorted `motivations`, `ai_state`, `script_target` |
| `npc_diplomacy` | seeded `.mob` diplomacy matrix, units with sides, command list | `GetDiplomacy` result bits for 36 + extra side pairs; per unit `side` and `IsEnemy` over sides 0..31 as a 32-bit mask |
| `npc_alarm` | start world tick, units with alerted flag / raise index / countdown, command and tick steps, query indices | `IsAlarm`, `AlarmTime`, `AlarmPosX`, `AlarmPosY` result bits per query index; each alerted unit's countdown |

Motivation entries: `guard` (point bits, radius and stay bits, or the name of
the `[Logic]` value used), `patrol` (point bits and each point's look entries),
`sentry` (point bits), `suspection`, `aggression` (`revenge`), `corpse_watcher`,
`player`, `fear` (`flag`), `follow` (`target` unit index; -1 none). The native
list is sorted by its type id (Guard 0, Patrol 1, Sentry 2, Suspection 3,
Aggression 4, CorpseWatcher 5, Player 6, Fear 7, Follow 10), the order in which
`0x5d5f60` keeps at most one motivation per type and one calm motivation.

### Remake mapping

The remake has no motivation list. `remake_ext_npc_commands.gd` maps:

- `GameUnit.mode`: `none` -> nothing; `sentry`/`guard`/`follow` -> that calm
  motivation from `mode_data`; `player` -> Player; any other mode is reported
  as `remake_mode_<mode>` (none occurred).
- Guard radius/stay below 0 -> `GuardRadius` / `GuardStayTime` (the remake
  resolves them through `ai.reg` when it runs the Guard; the native constructor
  `0x5d0b70` stores the configured value, which the native observation
  reports by name because the fixture writes distinct sentinel values).
- `UnitAI.mots(u)`: fight `standard` or `aggression` -> Aggression(revenge
  false), `revenge` -> Aggression(revenge true); `susp`, `corpse`, `fear >= 0`
  -> Suspection, CorpseWatcher, Fear(flag). The remake's no-leash distinction
  between `standard` and `aggression` has no native counterpart: both commands
  construct the same native object (`0x4ba710`).
- `ai_state` = meta `ai_state` (native AI +4); `script_target` = meta
  `ai_target` while `ai_state` is set (native AI +0x2c). `ScriptVM.ai_busy`
  discards `ai_target` whenever the state is 0.
- `blocked` = `GameUnit.blocked` (native unit +8 bit 0x800000); `side` =
  `GameUnit.faction` (native unit +0x250).
- Diplomacy: `GameWorld.diplomacy` is seeded with the same matrix; queries run
  `ScriptVM._call("GetDiplomacy"/"IsEnemy")`. Alarms: `UnitAI.alarm`,
  `invoke_alarm`, `_alert` and `tick()`; `world.ai._tick_n` starts at the
  supplied world tick.

A fresh native logic object (built by its constructor) has an empty list and AI
state 0; remake units start as mode `none` with `UnitAI.MOT_NONE`.

## Native code executed

Base executable:

- Command dispatcher `0x4b6760` (one single-command persistent body per step),
  expression evaluator `0x4b41e0` for every query.
- Unit logic constructor `0x545580` (AI at logic +0x980, built by `0x545990`).
- Motivation list add `0x5d5f60`, clear `0x5d4df0`, remove by type `0x5d6140`,
  patrol lookup `0x5d5e30`, patrol point add `0x5d12b0`, Guard/Sentry resets
  `0x5d6230`/`0x5d64e0`, Idle reset `0x5d7790`, Follow `0x5d7e40`,
  ResetTarget `0x5d7c30` -> descriptor rebuild `0x5d6630`, all motivation
  constructors and their `vtable+0x20` type methods.
- Diplomacy: `0x4554e0` (SetDiplomacy, one row, propagated to units of that
  side through the world unit container), `0x455660`, `0x455630`, unit mask
  setters `0x52e970`/`0x52e940`/`0x530120` (including the logic's `+0x98`
  notification `0x552cd0`).
- Alarms: `0x593fc0`; the AI tick `0x5d53b0` is executed from its entry up to
  `0x5d5413`, i.e. exactly its alarm countdown and raise.

Lost in Astral (`native_ext_npc_commands.NATIVE`, `cases_ext_npc_commands.ENTRIES`):

- Command dispatcher `0x4712c0`, evaluator `0x46cca0`, unit logic constructor
  `0x4c9a20` (AI built by `0x4c9930`, same logic +0x980 layout).
- Motivations: list add `0x51bd40`, clear `0x51af80`, remove by type
  `0x51be20`, UMSentry `0x464ea0`, UMGuard/UMGuardEx `0x466350`, patrol
  `0x463f20`/`0x517990`/`0x467720`/`0x51b460`/`0x5184d0`/`0x466120`,
  UMStandard/UMAggression/UMRevenge/UMSuspection/UMCorpseWatcher/UMPlayer
  `0x463fb0`/`0x463ff0`/`0x463f80`/`0x464030`/`0x4640c0`, UMFear `0x464060`,
  UMFollow `0x464f00`, Guard `0x51c980`, Sentry `0x51c9e0`, Idle `0x516bd0`,
  Follow `0x516e60`, ResetTarget `0x51cd80` -> descriptor rebuild `0x51ca30`.
  Commands 0x42 and 0xa4 fall to the dispatcher's default case (no-op), and
  UMAg rounds its mode through `0x43ca70`; both behave as in the base
  executable for these inputs.
- Diplomacy: table object `0x6b603c` (`0x4274c0` SetDiplomacy with unit
  propagation through world +0x40, `0x427440`, `0x427410`), SetEnemy
  `0x4273b0` -> `0x4ad950`, unit setters `0x4ad990`/`0x4ae3a0`, IsEnemy
  `0x463e20`.
- Alarms: world `0x6a33d8` (same table offsets), InvokeAlarm `0x4ee600`, AI
  tick `0x51c4d0` executed up to `0x51c532` (alarm countdown and raise).
- Motivation objects carry Astral vtables (e.g. Guard `0x627864`, Sentry
  `0x627774`), confirming the records come from the Astral constructors.

## Supplied boundaries (stubs)

CRT `operator new` `0x70056f` (zero-filled bump heap) and `operator delete`
`0x700598` (no-op; native destructors still run); temporary-expression cleanup
`0x4bec80`; the shared `Expressions` unit fixture (type/dead accessors, no-op
reference release); unit-constructor defaults for +0x244/+0x248/+0x250; the
unit<->logic<->AI attachment links; the `.mob` logic descriptor (ResetTarget);
the `.mob` diplomacy matrix at `0x7c2bb4` and each unit's spawn-time enemy mask;
a world unit container at world +0x40; `[Logic]` GuardRadius / GuardStayTime
sentinels at `0x7c53fc` / `0x7c53ec`; the world tick counter (world +0x64),
advanced by one per tick step before the alarm prologue (the remake's
`UnitAI.tick` also increments before counting down); the alerted flag, raise
index and countdown (AI +0x34/+0x35/+0x40, normally written by `0x5d6630`);
and `0x5ceed0` (ResetTarget's weapon/spell option rebuild from inventory).
Lost in Astral supplies the same boundaries at its own addresses: heap
`0x5ffa7b` / `0x5ffaa6`, cleanup `0x46a610`, diplomacy matrix `0x6b603c`,
`[Logic]` sentinels `0x6b878c` / `0x6b877c`, option rebuild `0x518100`.

## Limits

- Records only: no AI tick beyond the alarm prologue, no priority selection,
  movement, orders or combat. Remake orders issued by `_mode`/`Follow` are not
  observed.
- The native alarm raise iterates a spatial registry (world +0x12d70) that the
  fixture leaves empty, so alarm-driven descriptor switching of AI units is not
  exercised; the remake alarm units are therefore not registered in
  `world.units` either.
- Alarm queries use indices 0..4 (and fractions of them); native reads beyond
  the five-entry table are not compared.
- Diplomacy cases with sides 32/33 exercise native out-of-range writes and bit
  shifts; such sides do not occur in authored scripts.

## Proof the family can fail

A scratch copy of `game/` with three mutations (`UMSentry` swaps x/y,
`_diplo_in(0)` returns war, `invoke_alarm` stores `_tick_n + 1`) run with
`--game-source` turned 55 previously matching scenarios into mismatches (14
motivation, 11 diplomacy, 30 alarm; results `npc-commands-04-mutation`). The
unit tests also check that the validator rejects malformed states.

## Latest results

Base run `results/npc-commands-06` and Lost in Astral run
`results/npc-commands-07` (seed 20261020, fuzz 12): **213 scenarios each, 137
match, 76 differ** (134 motivation, 40 diplomacy, 39 alarm scenarios; both
sides repeat identically). The two executables produced identical native
observations for every scenario, so the same 76 scenarios differ in both
runs.

Divergences by cause (first differing field; expected native -> remake):

| Cause | Scenarios | Example first difference | Interpretation |
|---|---|---|---|
| `UMAg` (0xc8) not implemented | UMAg_mode_0..3,5,6; UMAg_after_standard_0..7; seeded_000, 001, 005, 017 (18) | `UMAg_mode_2`: motivations length 4 -> 0 | Native drops Suspection/Aggression/CorpseWatcher/Fear and adds a set by mode (0: Fear(1)+Susp+Corpse; 1: Fear(0)+Susp+Corpse; 2: Revenge+…; 3: Aggression+…; others: only the removal). Remake logs an unknown function. |
| `ResetTarget` (0xe8) does not rebuild the AI | ResetTarget_descriptor_0..5; seeded_003, 011, 012, 015, 018, 020 (12) | `ResetTarget_descriptor_1`: motivations 5 -> 0 | Native `0x5d7c30` rebuilds the motivation list from the unit's current `.mob` descriptor and resets the AI state; remake only clears target and orders. |
| `UMPatrol*` not implemented | UMPatrol_fresh, _points, _looks, _clear, _replaces_sentry, UMPatrolAddPointLook_without_point; seeded_008, 009, 014 (9) | `UMPatrol_points`: motivations 1 -> 0 | Native adds a Patrol (points snapped to 0.5 m cell centres, look entries); remake ignores all four commands. |
| `SetEnemy` (0x38) not implemented | SetEnemy_bit, _then_peace, _shift; diplomacy seeded_000, 003, 004, 007, 011 (8) | `SetEnemy_bit`: enemy_bits 36 -> 4 | Native ORs the side bit into the unit's hostility mask. Not used by authored base scripts. |
| `Sentry` (0x94) treated as `UMSentry` | Sentry_fresh, _after_fear1, _after_follow, _after_player; seeded_002, 010, 013 (7) | `Sentry_fresh`: motivations 5 -> 1 | Native `0x5d64e0` replaces the whole list with Sentry + Suspection + Aggression + CorpseWatcher + Fear(0) and resets AI state/target (like Guard); remake only sets the calm mode. 7 authored uses. |
| `UMSuspection`/`UMCorpseWatcher` not implemented | UMSuspection_fresh, UMCorpseWatcher_fresh, UMSuspection_CorpseWatcher_after_sentry; seeded_016, 019, 021, 023 (7) | `UMCorpseWatcher_fresh`: 1 -> 0 | Remake logs unknown functions. |
| Player motivation treated as calm | UMPlayer_then_UMSentry; motivation seeded_006 (2) | `UMPlayer_then_UMSentry`: motivations length 2 -> 1 | Native Player (type 6) is not calm, so a later UMSentry/UMFollow keeps it; the remake's `mode = "player"` is replaced. |
| `Follow` preconditions | Follow_missing_target, Follow_self, Follow_by_dead (3) | ai_state 6 -> 0 | Native sets AI state 6 for any present actor with logic, including a missing or self target and a dead follower; remake requires a distinct target and a living follower. |
| Fractional `SetDiplomacy` value | SetDiplomacy_value_3 (0.5), _4 (-0.5) (2) | relation_bits[9] 1.0 -> 0 | Native tests the float's sign; remake truncates to int first (`_diplo_in(int(...))`). |
| `SetPlayer` outside 0..31 | SetPlayer_out_of_range (40), SetPlayer_negative (-1) (2) | enemy_bits 0xffffffff -> 0 | Native `0x455660` returns -1, so the unit is hostile to every side. |
| Sides 32/33 | SetDiplomacy_side32_overflow, GetDiplomacy_side33_shift (2) | relation_bits[36] -1.0 -> 0 | Native row 32 aliases the enemy table and shifts use `side & 31`; remake treats them as out of range. Not authored. |
| Alarm query index rounding | query_rounding (1) | `IsAlarm(1.5)` 0 -> 1.0 | Native queries 0x67/0x8b/0x8c/0x8d round the index (half to even), InvokeAlarm truncates; the remake truncates both. |
| Countdown without a raise index | countdown_raise_zero; alarm seeded_009, 011 (3) | countdowns 0 -> 1 | Native counts down any alerted AI; remake only registers units whose descriptor names an alarm. No alarm differs. |

Everything else matches, including UMSentry/UMGuard/UMGuardEx/Guard storage and
defaults (`-0.0` stored explicitly), UMStandard/UMAggression/UMRevenge/UMFear,
UMFollow, Idle/UMClear/UMPlayer resets, BlockUnit, the SetSpellAggression and
SetPlayerAggression no-ops, one-directional SetDiplomacy with unit
propagation, SetPlayer within range, InvokeAlarm (forced, alarm 0 clearing,
truncated and rejected indices), alarm lifetime (alarms never expire) and the
75-tick countdown raise including two units raising the same alarm.
