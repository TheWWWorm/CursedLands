# Quest query builtins (`quest_query`)

Extension family of the [original-engine comparison suite](original-parity.md).
Files: `tools/parity/cases_ext_quest_query.py`, `native_ext_quest_query.py`,
`remake_ext_quest_query.gd`, `test_ext_quest_query.py`.

It covers condition builtins that the core `quest_predicate` family does not:

| Opcode | Builtin | Native path | Remake path |
|---|---|---|---|
| 0x51 / 0x52 | `Mana`, `MaxMana` | evaluator 0x4b41e0 reads stat record +0x34 / +0x38 | `ScriptVM._eval` (no handler) |
| 0x65 | `GetPlayer` | actor +0x250 (set by `SetPlayer`) | no handler; `SetPlayer` writes `GameUnit.faction` |
| 0x6a | `Sum` | iterates the group, evaluating the nested expression per member | no handler |
| 0x8f | `GetAIClass` | actor +0x324, −1 without an actor | no handler |
| 0xaa | `IsNight` | world night value 0x7affd4 | no handler |
| 0xbb | `IsInSquare` | point-in-rectangle on six literals | no handler |
| 0xd1 | `GetMercsNumber` | 0x591740: living party records − 1 | `GetMercsNumber` |
| 0xe1 | `GetLootItemsCount` | player record +0xec | no handler |
| 0xb4 | `GetUnitOfPlayer` | object evaluator 0x4b56c0, record `round(k)` | `GetUnitOfPlayer` |
| 0xe4 | `GetLeader` | object evaluator 0x4b56c0, single-player record 0 | `GetLeader` |

Object-returning builtins are read through `GetObjectID`, so the comparison
sees the selected actor's ID (0 for none).

Both executables are qualified: the base game (evaluator 0x4b41e0, object
evaluator 0x4b56c0, `GetMercsNumber` 0x591740) and Lost in Astral (0x46cca0,
0x46b8d0, 0x4e87d0). Astral uses the same opcode numbers and record offsets.

## Supplied boundaries

Actor stat records (mana, max mana), actor player number and AI class; the
world night value; player-zero lookup and single-player mode; party records
(IDs only) and the ID-to-actor lookups (base 0x55fb00 / 0x593aa0, Astral 0x4cd680 / 0x4ea290); the actor death
accessor (vtable 0xdc); the temporary object-slot block allocator 0x6fe8af
(stdcall, pooled on the script context; base 0x6fe8af, Astral 0x5fed90); the player-zero loot counter; group
membership. Everything else, including record indexing, rounding, death
filtering and the `- 1` in `GetMercsNumber`, executes natively.

On the remake side, `GameWorld.party_units` is replaced by the supplied actors.
Party record 0 is the protagonist in `CampaignState.heroes[0]`; later records
are active mercenaries in `CampaignState.mercs`. A record whose actor is absent
has a roster entry and no world actor. `ScriptVM._party_records` and
`_story_records` run unchanged.

## Limits

Queries only. No mana regeneration, spellcasting, day/night simulation, party
management, looting or multiplayer ownership. The native `GetLeader` network
branch (0x41a020) is not taken.

## Results (2026-10-21)

`results/quest-query-04`: 123 scenarios, **71 match, 52 differ**, repeatable on
both sides. Every divergence is listed below (original → remake).

### Builtins the remake does not implement

These evaluate to `null` (read as 0) with an "unknown function" warning:
`Mana`, `MaxMana`, `IsNight`, `IsInSquare`, `GetPlayer`, `GetAIClass`,
`GetLootItemsCount`, `Sum` (38 scenarios, e.g. `Mana_7.5_30` 7.5 → 0,
`IsInSquare` boundary/degenerate cases 1 → 0, `GetAIClass_missing` −1 → 0,
`Sum_hp_0_1_2` 30 → 0). None is used by authored base-campaign scripts; they
are part of the original script language and available to modified maps.

### Party and leader queries (used by authored scripts)

| Scenario | Original | Remake | Meaning |
|---|---|---|---|
| `GetMercsNumber_solo_dead` | −1 | 0 | Original counts living records including the protagonist, then subtracts one |
| `GetMercsNumber_dead_hero` | 0 | 1 | Same: a dead protagonist lowers the count |
| `GetMercsNumber_all_dead` | −1 | 0 | Same |
| `GetLeader_solo_dead`, `_dead_hero`, `_all_dead` | 100 | 0 / 101 / 0 | Original returns record 0's actor even when dead; remake skips dead or hidden members |
| `GetUnitOfPlayer_*_1.6` | slot 2 | slot 1 | Original rounds the index to nearest; remake truncates |
| `GetUnitOfPlayer_absent_merc_1`, `_1.4` | 0 | 102 | Remake skips a record without an actor, shifting later slots |
| `GetUnitOfPlayer_absent_merc_2` | 102 | 0 | Same shift |
| `GetUnitOfPlayer_other_player` | 0 | 100 | Single-player original has no player 1; remake ignores the player argument |

### `GetLeader()` arity

The original builtin takes **no parameters** (`GetLeader O`). Authored
triggers in `z18q1.mob` (VCheck#1#25, #27, #31 and a `UMFollow` body) and
`z7q3.mob` (VCheck#3#1) call `GetLeader( )`. The remake handler reads
`v[0]`, which is out of range for that call and raises a script error, so those
conditions cannot become true. The family passes an extra literal (ignored
natively) so the run can still compare leader selection. This is recorded as a
finding; production is unchanged.

Lost in Astral (`--campaign lost_in_astral`, `results/quest-query-astral-01`):
the same 123 scenarios, **71 match, 52 differ**. The Astral executable produced
observations identical to the base executable for every scenario, and the
divergence set is the same.

## Can it fail?

Yes: 52 scenarios differ, and matching cases (e.g. `GetUnitOfPlayer_two_mercs_1`,
`GetMercsNumber_two_mercs`, `in_square_-1e-06_5`) show that equal results are
compared exactly rather than accepted by default.
