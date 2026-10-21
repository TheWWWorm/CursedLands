# Quest script scheduler (`quest_scheduler`)

Extension family of the [original-engine comparison suite](original-parity.md).
Files: `tools/parity/cases_ext_quest_scheduler.py`, `native_ext_quest_scheduler.py`,
`remake_ext_quest_scheduler.gd`, `test_ext_quest_scheduler.py`.

It compares **when trigger blocks fire and how script threads are scheduled**:
the original per-tick scheduler against `ScriptVM.tick` / `_run` / `spawn` /
`fire_event`. State-changing commands, NPC commands and dialogue are covered by
other families; here bodies only assign numeric globals, sleep, wait, start
scripts and `KillScript`.

## Inputs

Each scenario is a small program in the original script language: numeric
`GlobalVars`, `DeclareScript`/`Script` blocks (`if ( conds ) then ( body )`), a
`WorldScript`, external global changes per 55 ms logic tick and optional
briefing completions (`#OnBriefingComplete( nPlayer, szComplete )`). Inputs
never contain expected values. Three boot modes put the program in motion:

| Boot | Start of the program |
|---|---|
| `world` | The `WorldScript` body starts the scripts (authored maps start with `Sleep(2)` and `VCheck(NULL)` calls). |
| `event` | A briefing completion at tick 0 runs an `#OnBriefingComplete` handler whose first slice (after `KillScript`) is the start body. |
| `handler` | The script under test is itself the `#OnBriefingComplete` handler, completed at tick 0. |

The 42 fixed scenarios follow authored base-campaign shapes (zone1
`VCheck#0#1` → `VTriger#0#15` check/trigger chains; basecam `VCheck#0#309`
if/else block pairs at the night/day thresholds; per-unit copies; sleeping
trigger bodies with `Sleep(0)`, `Sleep(-1)`, `Sleep(0.5)`, `Sleep(2.5)`,
`SleepUntil`; bz10k-style briefing handlers with string and float
parameters; `KillScript` before, after and between assignments, after a
`Sleep` and in `WorldScript`). The fuzz set adds `fuzz` random multi-block
handlers (16 ticks) and `fuzz` random 2–4 script programs started from either
`WorldScript` or an event (calls form a DAG), seeded from `seed ^ 0x4bf000`.
In the base MOBs, 3355 blocks start with `KillScript`, 3 kill later in the
first slice, 2 never kill and none kill after a `Sleep`; 126 scripts have an
if/else pair of blocks and handlers have up to 98 blocks.

## Native routines

All of these execute in Unicorn on the user's `game.exe`:

| Address | Role |
|---|---|
| 0x4bf000 | Scheduler pass (ECX = script context; runs when ctx+0x1a8 ≠ 0). |
| 0x4bcc60 | Registers a `WorldScript` body as a thread (killed pointer 0) at the head of the thread list. |
| 0x4bb520 | Block gate: evaluates conditions with 0x4b41e0 until the first false one; if all hold calls 0x4bc420. |
| 0x4bc420 | Body dispatch: builds a thread (body, ip 0, run counter 0, wait −1, killed pointer = instance, copies of the locals), runs the first slice with 0x4b6760 and queues the thread at the head of the thread list if it returns nonzero. |
| 0x4b6760 | Command dispatcher (`Sleep` 7, `SleepUntil` 0xde, `KillScript` 0x79, script call 8, assignment 0x78). |
| 0x4c7c90 / 0x4bb6a0 | Script call: new instance at the head of the trigger list from declaration ctx+0x90 + n·0xc0, then parameter binding. |
| 0x4b41e0 | Expression evaluator. |

Layout used to build the fixture: thread list object ctx+0x15c (head +0x160,
tail +0x164, count +0x168, node 0xbc bytes `[next, prev, thread]`), trigger
list object ctx+0x140 (head +0x144, node 0xc8 bytes `[next, prev, instance]`),
instance/declaration 0xc0 bytes (+0 killed, +0x10/+0x14 blocks, frame at +0x20
with floats +0x24, strings +0x4c, objects +0x74, groups +0x9c), numeric globals
at ctx+0xa4, local bindings at command +0x54 and global bindings at +0x68
(`[type, slot, index]`, decoded by 0x4b3f60). Command records are compiled by
`native_quests.Expressions.compile`; script-call records get the argument
counts 0x4bb6a0 checks (+0xc, +0x20, +0x34).

## Supplied boundaries (stubs)

- CRT `operator new`/`delete` 0x70056f/0x700598 and MFC `CFixedAlloc`
  0x6e6bf1/0x6e6c80: a fixture bump heap, frees ignored. The four fixed pools
  0x7c8b70/48/20/f8 are never constructed in a bare replay (CRT static
  initialisers do not run), so the fixture writes their element sizes.
- Kernel32 `lstrlenA`/`InterlockedIncrement`/`InterlockedDecrement` import
  slots 0x73b250–0x73b258 (used by CString copies of string parameters).
- Temporary-command cleanup 0x4bec80 (the fixture has no temporaries).
- Fatal script error 0x480080 records its message and halts the replay
  (the original calls `exit`).
- CString destructor and temporary strings, player lookup and single-player
  network mode (shared quest fixture).
- Briefing completion 0x592090 is represented by what it does: it compiles
  `WorldScript( GSSetVar( p,"key",2 ) #OnBriefingComplete( p, "key" ) )` and
  registers it through 0x4bcc60. The fixture registers the equivalent body
  (numeric flag global set to 2, then the handler call). Its thread is excluded
  from the observations.
- Remake: `Briefings.tick` (automatic zone-briefing polling) is replaced by a
  no-op; `Briefings.complete` is mirrored by setting the flag global and calling
  the production `ScriptVM.fire_event` as it does.

## Remake side

The program text is parsed by the production `ScriptParser`; `_start_world`
starts the `WorldScript`; every step is one `ScriptVM.tick(SLEEP_UNIT)`.
`SchedulerVM` overrides `_eval`, `_once_per_world` and `_run` only to record
and then calls the production method.

## Observation mapping (one state per 55 ms tick)

| Field | Native | Remake |
|---|---|---|
| `trace` `c:S.b.c` | 0x4b41e0 called with the root of condition c of block b | `_eval` called with that condition's AST node |
| `trace` `fire:S.b` | 0x4bc420 called with block b's body | `_once_per_world` (called by `_run` exactly when a block's conditions hold) |
| `trace` `run:L` | 0x4b6760 called for a queued thread with statements left (ip < count) | `_run` for an instance with frames (excluding an empty `WorldScript` body, which the original drops without running) |
| `globals` | f32 bits of ctx+0xa4 | `ScriptVM.globals` as f32 bits |
| `scripts` | trigger-list nodes per script | non-killed, non-`WorldScript` instances per script |
| `bodies` | queued threads with ip < count, per body label | instances with frames, per body label |
| `fatal` | message passed to 0x480080 | always "" (the remake has no fatal script errors) |

Body labels are `S.b` for block b of script S and `World`. The briefing
carrier thread is not observed. After a fatal error the native replay stops
and later steps repeat the fatal state.

## How the schedulers work (answers)

- **Pass order.** Native 0x4bf000 runs *all queued threads* (newest first),
  then polls *all trigger instances* (newest first). The remake visits
  instances newest first and, per instance, either polls it (no frames) or
  resumes its body, so polls and resumes interleave.
- **Conditions.** Both evaluate a block's conditions in order and stop at the
  first false one. Native evaluates every block of an instance each pass and
  fires *every* true block; only a `KillScript` in a fired body's first slice
  stops it (the instance node is removed and later blocks are skipped). The
  remake fires only the first true block.
- **Sleeping body.** Native keeps polling the instance and starts another
  concurrent body thread every pass its conditions hold. The remake does not
  poll an instance while its body runs.
- **Re-arm.** Without `KillScript` a block can fire again as soon as its body
  is done; on both sides a body finished in its first slice lets the block
  fire again the next tick (native keeps the finished thread queued for one
  more pass; it is not observed as running).
- **KillScript.** Native: allowed only in a body's first slice, which runs
  synchronously inside 0x4bb520 with the killed pointer set. It disposes the
  trigger instance (and skips the rest of its blocks this pass) but not the
  body, which runs to completion. In a resumed slice or in `WorldScript` the
  pointer is 0 and 0x4b6760 raises the fatal error "KillScript command not
  allowed here" (the game exits). The remake marks the instance killed at any
  time and keeps going.
- **New threads.** Native: a script started by a running thread (`WorldScript`
  or a resumed body) is polled in the same pass because the trigger walk comes
  after the thread walk; a script started from a first slice (inside the
  trigger walk) is inserted at the list head and first polled next pass. The
  remake polls every instance spawned during a tick in the next tick.
  `#OnBriefingComplete` handlers are created by the carrier thread in the
  next native pass and polled once there. The remake's `fire_event` runs the
  handler immediately, outside the tick; the following tick then polls (or
  resumes) it again and also polls the scripts its first slice started.
  `SendEvent` (0x39 → 0x66c300) and `SendStringEvent` (0x3a → 0x66c380) are
  network broadcasts in the original and never start script threads; the
  remake also starts none (not compared).
- **Sleep.** Native counts 0x4b6760 calls per thread (the first slice counts)
  and pauses while `counter − start < round_half_even(n)`; `Sleep(n ≤ 0.5)`
  does not pause. The remake's `sleep_ticks`/`NavGrid.round_even` gives the
  same resume ticks once the handler timing difference is removed (all
  `body_sleep_*` scenarios match in the diagnostic run below). Native polling
  continues during a sleep; the remake's does not (see above).

## Limits

Numeric globals, `NULL` object parameters and float/string parameters only. Not
covered: units and AI (`SleepUntilIdle` 0xb9 waits on unit state), `For`
loops, save/load of running threads, multiplayer once-per-world rules, and the
five extra immediate 0x4bf000 passes 0x592090 makes after registering the
briefing carrier when its mode field `game+0x12d64` is 3 (the meaning of mode 3
was not established: the field is compared with 1, 3 and 4 in several
routines and the only writer found stores 0). Astral is not qualified
(`contracts("lost_in_astral")` is empty).

## Proof that the family can fail

- A fixture bug was caught by the comparison itself: before the CFixedAlloc
  pool sizes were supplied, overlapping allocations made a native float
  parameter read 3.0000005 instead of 3 in `briefing_handler`.
- An `--game-source` scratch copy with `KillScript` also clearing the body's
  frames (`inst.frames = []`) turned the two matching fuzz scenarios
  `fuzz_blocks_000` and `fuzz_blocks_009` into mismatches (`globals.o0` 2 vs 0
  and 1 vs 0) and changed 51 of 66 remake traces (`quest-scheduler-07`).
- A scratch copy with `Sleep` holding one extra tick (`<=`) changed 32 remake
  traces and nine first differences (`quest-scheduler-06`).
- `test_ext_quest_scheduler.py` checks that a one-sided change of a trace or
  fatal field is reported and that malformed states are rejected.

## Latest results

Run `results/quest-scheduler-05` (seed 20261020, fuzz 12): 66 scenarios,
**4 match, 62 differ**, repeatable over two captures per side.

Matching: `declared_never_started`, `kill_after_assignments`,
`fuzz_blocks_000`, `fuzz_blocks_009`.

Divergence mechanisms (first difference per scenario in the final report):

| Id | Mechanism | Scenarios |
|---|---|---|
| E | `fire_event` runs the briefing handler immediately and the same tick processes it again; its child scripts are polled in that tick (native: handler polled once in the carrier's pass, children next pass). | 30 scenarios whose only difference this is (they all match when the immediate `_run` in `fire_event` is removed in a scratch copy, run `quest-scheduler-08`); it also shifts or masks the first difference of 14 of the others (listed under their own mechanism). |
| W | A script started by `WorldScript` or by a resumed body is polled in the same native pass; the remake polls it one tick later. | `authored_check_trigger_chain`, `authored_if_else_world_start`, `authored_if_else_late_start`, `world_sleep_then_start`, `spawn_from_world_first_tick`, `spawn_order_three_world`, `per_unit_copies_world`, `briefing_handler_sleeps`, `spawn_from_resumed_slice`, `fuzz_scripts_001/003/005/007/009/011` |
| B | All true blocks of an instance fire natively in one pass; the remake fires only the first. | `blocks_without_kill`, `second_block_kills`, `fuzz_blocks_003/005/007/008/010`, `fuzz_scripts_004` |
| C | Native re-dispatches a block while its earlier body still sleeps (concurrent bodies); the remake does not poll a running instance. | `rearm_sleeping_body`, `rearm_sleep_until_body`, `fuzz_blocks_006`, `fuzz_scripts_010` |
| D | Native runs all queued threads before any poll; the remake interleaves by instance age. | `cross_script_same_tick`, `fuzz_scripts_002`, `briefing_handler` (carrier/World thread before the handler poll) |
| F | `KillScript` after the first slice (resumed body or `WorldScript`) is fatal in the original; the remake accepts it. | `kill_after_sleep`, `world_kill` |

Every scenario's first differing field (original versus remake) is in
`report.md` of the result directory. Run `quest-scheduler-08` is diagnostic
only (scratch copy, production code unchanged) and shows the differences that
remain once mechanism E is removed.
