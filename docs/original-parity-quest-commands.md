# Quest command effects (`quest_cmd_*`)

Extension family of the [original-engine comparison suite](original-parity.md).
Files: `tools/parity/cases_ext_quest_commands.py`, `native_ext_quest_commands.py`,
`remake_ext_quest_commands.gd`, `test_ext_quest_commands.py`.

It checks what quest trigger bodies do to campaign state. Each scenario is a
persistent command body. The original runs it through the native command
dispatcher `FUN_004b6760`, tick by tick, as `native_quest_programs.py` does. The
remake runs the same body through `ScriptVM._run`, with a `Session` and
`CampaignState` fixture. After every tick, both sides report the full resulting
state:

| Field | Original (native memory) | Remake (production state, mapped) |
|---|---|---|
| `gs` | Player zero's GS hash table at player +0xc4: bucket count, element count (+0x10), and every non-empty bucket chain from its head, as `[key, float32 bits]` | `CampaignState._gs_table(0)` capacity, count and bucket chains; values from `get_var(0, key)` |
| `bag` | Player bag list (+0xe4 head … +0xec count): the script ID (+0x4c) of each item, in list order | `CampaignState.quest_items` keys in insertion order, mapped to `quest_items.script_id` from `GameData.db` |
| `money` | Player +0xc0 | `CampaignState.money` |
| `levers` | Lever record +0x238 state; permission = flag 0x80000 clear at +8 | `GameWorld.levers[uid].state` / `.enabled` |
| `groups` | Group array entries (+4, count +8), mapped back to fixture unit indices | Global group `Array`, mapped to fixture unit indices |
| `journal.recording` | QStart's quest-ID CString at 0x7aa60c | `ScriptVM._q_recording` |
| `journal.compiled` | One entry each time QFinish hands its generated script to the compiler: quest ID and the objective records (0x7aa5fc, count 0x7aa600) as `[kind, text, float32 bits]` | `ScriptVM.qobjs` entries with `defined = true`, in insertion order. `QObjArea` and `QObjGetItem` store their number as text, so they map to `("", bits(float(text)))`. The other objective kinds map to `(text, bits(second argument))`. |
| `globals`, `observed_bits` | Script globals; observation expressions evaluated by 0x4b41e0 | `ScriptVM.globals`; `ScriptVM._eval` |
| `finished`, `killed` | Thread instruction pointer at the end of the body; KillScript flag | `Instance.frames` is empty; `Instance.killed` |

A `For` body records its iteration order in an ordinary global accumulator
(`order = order * 10 + GetObjectID(i)`). The executable evaluates it natively.

## Commands and native paths

The table follows authored base usage counts from `re/usage.txt`.

| Command (uses) | Opcode | Native path executed |
|---|---|---|
| AddObject (1881) | 0x22 | 0x4b2ef0: binary search by pointer, de-duplicated sorted insert, array growth |
| GSSetVarMax (1450) | 0x98 | 0x66ee40: 0x460af0 lookup, `v < old ? old : v`, then 0x460bc0 only on change |
| GSSetVar (226) | 0x7f | 0x66edd0 → 0x460bc0: hash `h*5+signed char`, 0x461750 growth/rehash before every insert, head insertion, value 0 erases |
| EraseQuestItem (219) | 0x93 | 0x665740: removes the first type-0x3009 item with the script ID, then frees list blocks when the bag becomes empty |
| For (188) | 0x6b | Iterates the group from the last index to the first. The count is read once. Each body runs through a recursive 0x4b6760 with swapped thread state. |
| SwitchLeverState (78) / Ex | 0x91 / 0x9e | 0x52b7a0: state < 0 means next state (wrapping only when cycled); otherwise clamp to 0..states−1 |
| QuestComplete (101) | 0x9f | not covered; see Limits |
| GiveQuestItem (34) | 0x92 | 0x594ab0 (supplied factory) → 0x4c98c0/0x4c98f0 temporary list → 0x665430 tail append |
| QStart / QFinish (26) | 0xd5 / 0xd6 | 0x4baa40 clears the objective array and sets the quest ID. 0x4baab0 formats the Su0..SuN script text with the real CString/printf code, then resets the quest ID. |
| QObj* (63) | 0xd7–0xdd | 0x4bae10 appends `{opcode, CString, float}` to the global array (0x4cdf40 growth) |
| GiveMoney (10) | 0xa7 | player +0xc0 += `__ftol(n)`, then 0x665430 with an empty list |
| EnableLever (3) | 0xcc | 0x52bad0: 0 sets flag 0x80000; any other value clears it |
| GSDelVar (3) | 0x82 | 0x66eef0 → 0x460db0 |
| RemoveObject (0) | 0x23 | 0x4b2da0 index lookup, 0x4c2200 removal |
| HaveItem, GetMoney, GetLeverState, GSGetVar, GroupSize, GroupHas | evaluator | 0x4b41e0 (observation only) |

The empty GS table is built by the native constructor 0x581790. It requests
100 buckets, and 0x408a50 rounds that up to the prime 193. The scenario's
initial variables are then inserted with native 0x460bc0 in the listed order.
Initial bag items go through native 0x4c98c0/0x4c98f0/0x665430. Groups start
empty; only native AddObject fills them. QFinish's generated text for the
authored `z17q1` pattern looks like this (diagnostic, not compared):

```text
Script Su0(if(
IsUnitVisible( GetObject(1000061) )
)then(
KillScript()
Su1()
GSSetVar(0,"q.z17q1.z17q1.1",2)
GSSetVar(0,"q.z17q1.z17q1.2",1)
)
)
...
Script Su2(if()then(KillScript()
QuestComplete(0,"z17q1")
GSSetVar(0,"q.z17q1.z17q1", 2)
)
)
WorldScript( Su0() )
```

## Supplied boundaries (contract `stubs`)

- Win32 imports (`lstrlenA`, `InterlockedIncrement/Decrement`,
  `Enter/LeaveCriticalSection`). Each IAT slot points to a stub, and any other
  import reached raises an error.
- `operator new`/`delete` (0x70056f/0x700598) and the MFC CString size-class
  allocator (0x6e6bf1/0x6e6c80), served by a bump allocator. Frees are no-ops.
- The player lookup 0x594180 returns player zero only (single player). The
  network check 0x57f440 reports single player.
- Item construction by name, 0x6ac930, called from 0x594ab0. Names from
  `items.idb` "quest items" (case-insensitive) produce a type-0x3009 record
  with the database script ID. Unknown names produce none.
- The player's client notifications (vtable +0x44 items received, +0x4c item
  removed) and its embedded network stream (+0x48, vtable +8). Calls are
  recorded but not compared.
- The lever database lookup 0x464750 returns no record, giving the native
  default time of 10. The world getter 0x455950 returns a world whose vtable
  +0x68 reports no active map, so figures, footprints and sounds are not
  updated.
- The script compiler 0x4d23a0 records QFinish's text. It does not compile,
  spawn or schedule the Su scripts.
- The temporary-value cleanup 0x4bec80 (these bodies allocate none) and the
  fixture vtable for unit and lever type, death and release.
- Static initial state: QStart's quest-ID CString starts as `afxEmptyString`,
  and the player bag block size is 10. The CRT float-format initializer
  0x6e7294 runs natively, because QFinish's `%f` formatting needs it.

Everything else listed above executes as original instructions.

## Limits and what is not covered

- **Base executable only.** `contracts("lost_in_astral")` is empty. Astral's
  dispatcher (0x4712c0) inlines these paths differently: GS through
  0x5943e0/0x594450/0x5944a0 with a separate max helper, and the bag through
  0x58ef20/0x58f0e0. It needs its own qualified address table.
- **Group order.** Native groups are sorted by object address. Fixture records
  are allocated in ascending input-index order, so the native order here is
  index order. In the original game the order depends on allocation history.
- **QuestComplete (0x9f) is not covered.** It needs the quest database lookup
  (0x4c9c90) and the party experience distribution 0x5911c0, which walks the
  player's live unit list and stats. Neither fits a bounded fixture. The remake
  path also involves SideQuests, restocking and smile faces.
- **SendStringEvent/SendEvent are not covered.** Natively (0x66c380/0x66c300)
  they only queue a network message to every player. The remake instead
  applies the client-side effect (`_string_event`) or does nothing, so neither
  side has comparable state.
- **GiveUnitQuestItem / RemoveQuestItem (1 and 6 authored uses) are not
  covered.** They act on a unit's carried inventory, which this fixture does
  not model.
- **ForIf is not compared.** It has no authored use in either campaign, and the
  remake parser has no ForIf form.
- No network replication, co-op per-player stores, LMP ownership, pickup
  messages, objective progress or Su-script execution.

## Proof that the family can fail

`results/quest-commands-02-mutant` ran the same inputs against a scratch copy
of `game/` (`--game-source`) with three mutations:

- `GSTable.put` appends instead of head-inserting.
- Cycled levers clamp instead of wrapping.
- `GiveMoney` adds one extra.

27 scenarios that match on the real source then differed. The first
differences were the chain order in every collision and growth scenario, every
money scenario, and `next_wraps_cycled` and `fuzz_7`. The unit tests also check
that the comparator reports single-field mutations of these states, and that
the validator rejects malformed observations.

## Results (2026-10-21)

`results/quest-commands-03`: **143 scenarios: 110 match, 33 differ.** Both
sides are repeatable. Every divergence is listed below, as original → remake,
grouped by cause.

Group storage and `For` (13 scenarios + 6 fuzz):

- `add_order` `G[0]` 0 → 2, `for_copy_into_second_group` `G[0]` 0 → 2,
  `for_dead_member` `G[0]` 1 → 3, and `groups/fuzz_0,3,9,10,11` (the first
  member differs). The native group array is always sorted by object address
  and de-duplicated. The remake keeps insertion order.
- `for_order` `order` 213 → 231, `for_nested` 12133233 → 32331212,
  `groups/fuzz_5`. Native `For` visits members from the last array index to
  the first. The remake visits them first to last. This reversal does not
  depend on addresses. Any order-dependent `For` body (counters, first match,
  `Run`/`UMGuard` issue order) runs in the opposite order.
- `remove_existing_and_missing` `G[1]` 2 → 1, `group_queries_after_changes`
  (length 2 → 3), `remove_then_for` `order` 21 → 312, and
  `for_body_removes_current` (`order` 213 → 312, final `G` [] → [0,1,2]). The
  remake has no `RemoveObject`: it logs "unknown function" and the member
  stays. Authored base scripts do not call it.
- `for_body_adds_member` `order` 23 → 12. Native `For` reads the count once and
  indexes the live array, so an insertion during the loop shifts the remaining
  members. The remake iterates a snapshot.
- `for_body_sleep_unauthored` `finished` true → false. Natively, a `Sleep`
  inside a `For` body ends that member's body early: the rest of it never runs
  (`order` stays 0) and the loop continues. The remake suspends the whole
  thread and resumes the body later. Authored scripts only sleep after the
  loop.

Quest-item bag (5 scenarios + 4 fuzz):

- `give_duplicate_then_erase_once` `bag` length 2 → 1 (final [17] → []), `erase_head` and
  `erase_tail` (final `bag` [48,52,48] → [48,52] and [25,48,48] → [25,48]), and
  `items/fuzz_0,1,2,8`. The native bag is a list that keeps duplicate copies,
  and `EraseQuestItem` removes only the first. The remake stores quest items as
  a set, so a second `GiveQuestItem` adds nothing and one erase removes every
  copy. `HaveItem` after give, give, erase is 1 natively and 0 in the remake.
- `items/absent_player_one` `bag[0]` 29 → 8. In single player, natively
  `GiveQuestItem(1, …)`, `EraseQuestItem(1, …)` and `GiveMoney(1, …)` are
  no-ops because there is no player 1. The remake ignores the player number
  outside LMP.

GS variables (2 scenarios):

- `gsvar/absent_player_one` first chain bucket 97 → 112. The same player-index
  rule applies: the remake writes `GSSetVar(1, …)` and `GSSetVarMax(1, …)` into
  the shared store and deletes for `GSDelVar(1, …)`. Authored scripts use
  `GSSetVarMax(nPlayer, …)` 67 times, with `nPlayer` 0 in single player.
- `set_nan_then_max` chain count 0 → 1. Natively, `GSSetVar` with a NaN value
  (here `Div(0,0)`) takes the "== 0" branch, because the x87 compare is
  unordered, so it erases or skips the key. The remake stores NaN (bits
  0xffc00000). The following `GSSetVarMax(…, 5)` then yields 5 natively and
  leaves NaN in the remake.

QStart/QObj*/QFinish (6 scenarios):

- `objective_without_qstart` `compiled` length 1 → 0. Natively QFinish always
  compiles: an objective recorded without QStart produces a chain with the
  empty quest ID. The remake ignores QObj* outside a recording.
- `restart_same_quest` `objectives[0]` QObjKillUnit → QObjArea. A second QStart
  of the same quest clears the native array. The remake keeps the old
  objectives and appends the new ones.
- `second_registration_same_quest` `compiled` length 2 → 1, and
  `objectives_after_finish` 2 → 1. Each native QFinish compiles a new Su chain;
  QObj* after a QFinish are appended to the retained array and compiled by the
  next QFinish. The remake registers each quest once and ignores QObj* after
  QFinish.
- `mixed_case_quest_id` quest `Z17Q1` → `z17q1`. The remake lower-cases the
  quest ID, so the generated `q.Z17Q1.Z17Q1.*` variable names differ.
  Authored IDs are lower case.
- `seventeen_objectives` objective count 17 → 16. The remake caps a quest at 16
  objectives; the original has no cap.

All other covered behaviour matches. This includes:

- GS bucket placement, collision chains, update-in-place, zero and −0 erase,
  `GSDelVar` at the chain head, middle and tail, and rehash from 193 to 389.
- `GSSetVarMax` on a new, equal, lower, higher, fractional or negative key,
  including NaN on an existing key and the authored counter pattern.
- Latin-1 and case-sensitive keys, `gtime`, and the empty key.
- Bag append and erase order, a fractional erase ID, and the empty-bag reset.
- Money truncation (7.9 → 7, −7.9 → −7).
- Lever clamping, next/wrap, single-state levers, the huge state value 3e9,
  Ex times, permission and non-lever targets.
- Objective records and float values (0.1, 2.5, −1, 123456789) for the
  supported QStart/QFinish patterns.
