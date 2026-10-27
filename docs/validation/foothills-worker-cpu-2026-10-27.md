# Foothills worker CPU — 27 October 2026

Follow-up to [#119](https://github.com/TheWWWorm/CursedLands/issues/119): a solo
campaign's separate simulation process cannot sustain fast speed in the
Foothills on slower processors. Based on local main `34a17e14`, branch
`perf/foothills-worker-20261027`. Hardware: Ryzen 9 5950X; other workstation
tasks were active. These are local CPU measurements, not predictions for a
player's CPU.

## Where the worker's time goes

Released 1.32.0 runtime, headless authority loaded from a fresh Foothills save
(214 units), 30 frames per second, fast speed (37 ticks/s).

| Part | Cost |
| --- | --- |
| World tick | 8.6 ms/tick |
| Script VM (quest triggers) | 5.3 ms/tick, of which AI perception 1.8 |
| Unit logic | 2.4 ms/tick |
| `GameUnit._process` × 214 | 2.2 ms/frame |
| `GameSound` (authority danger flag ≈ 1.0) | 1.5 ms/frame |
| `EIUnitModel._process` × 214 | 0.3 ms/frame |
| `TerrainDetails` grass streaming | 0.3 ms/frame |

Once the worker falls behind, frames lengthen and per-frame work is amortized;
the per-tick cost sets the sustainable speed. The script VM is the largest
part. Each tick it polls 139 triggers; 42 copies of
`GroupSize(GroupCross(UnitSee(this), Heroes))`, 42 `IsDead(this)` and a dozen
`GroupSee`/`UnitSee` checks over named groups dominate. Apart from perception,
the cost was GDScript dispatch: a 55-label `match` reached `IsDead` after about
2 µs, and the `UnitSee` form built full lists and filtered them with lambdas.

## Change

`ScriptExpressionKernel` now evaluates `GroupSize`, `IsDead`, `UnitSee`,
`GroupSee`, `GroupHas` and `GroupCross`, including the lazy
`GroupHas(UnitSee/GroupSee(x), y)` and `GroupCross(g, UnitSee/GroupSee(x))`
forms. Each watcher's noticed list still comes from `ScriptVM._noticed`, which
owns the AI refresh, its once-per-world-time cache and the per-tick memo; the
kernel calls it in the interpreter's order and only combines the lists. Unit
tests follow `_unit`, `_group` and `_sees_has`, including looted, freed and
derived units. Malformed shapes, wrong arities and kernels without the unit
class return to the interpreter before evaluating anything. The kernel holds
the `GameUnit` script by instance ID, so it never extends that class's
lifetime. `-- --ei-script-expressions` and older libraries keep the complete
interpreter.

The trigger poll now asks each block's (cached) condition purity once rather
than again through a lambda after an idle poll, and the party-check lookup no
longer allocates a dictionary. Both are the same decisions in the same order.

No AI rule, perception cadence, trigger order, random draw, save field or
network message changes.

## Measurements

`tools/benchmarks/campaign_cpu.gd`, 600 complete 55 ms ticks from the same
Foothills save, frozen packs exported from this branch with the committed
(`A`) or new (`B`) VM and library, ABBA order, release 1.32.0 engine:

| | A: tick total | B: tick total | A: p50 tick | B: p50 tick |
| --- | ---: | ---: | ---: | ---: |
| Samples | 3.423, 3.487, 3.407, 3.439 s | 2.684, 2.702, 2.690, 2.782 s | 5.45–5.57 ms | 4.24–4.39 ms |
| Median | 3.431 s | 2.696 s (−21.4%) | 5.49 ms | 4.25 ms (−22.6%) |

The stock 4.7 editor gives 3.829 s versus 2.976 s (−22.3%). The real-frame
worker probe at fast speed uses 0.356–0.369 of a core with `A` and 0.316–0.320
with `B` (−13%; per-frame work is unchanged). Instrumented editor runs put the
script VM at 5.8–6.0 versus 4.5–4.8 ms/tick with perception unchanged.

A processor that sustained about 1.6× in the Foothills should now approach
the full 2.04× fast rate. That is an inference from the per-tick reduction,
not a measurement on slower hardware.

## Equivalence and regressions

`script_expression_native` compares each query against the interpreter for 18
value kinds, every watcher type, the Foothills shape, argument order with
mutating and random arguments, malformed shapes, an unconfigured kernel, and
live death/removal. It passes 22,731 assertions with the stock editor, the
Linux release runtime and the Windows release executable under Wine 11.20. With
the committed library it fails exactly the six native-availability assertions.

Release-runtime registered checks passed: `foothills_campaign_flow`,
`foothills_actor_clock`, `worker_overload_recovery`, `side_quest_lifecycle`,
`corpse_memory_save`, `dead_deer_cast_source`, `campaign_feedback` and
`dialogue_clock_coop`. Unregistered script programs passed: `script_clock`
(1,408), `script_clock_coop` (17, LiA data), `script_parity_boundaries`,
`script_dead_predicates`, `script_future_queries` (1,434), `script_perception`,
`script_hero_references`, `script_quest_waits`, `lever_transition_save`,
`lever_use_flags`, `z19q3_levers`, `catacomb_group_lever` (LiA data),
`quest_actor_removal` and `save_actor_refs`. `script_scheduler` passes all 15
assertions; its exit reports 3 leaked resources, identically on unmodified code.
Under Wine, `script_perception` and `script_dead_predicates` also pass.
`foothills_campaign_flow` cannot start its separate authority process under
headless Wine and Wine's debugger catches a page fault; a pack exported from
unmodified source fails identically, so the Windows flow is covered only by
the Linux runs.

The Linux library rebuilt from unmodified source reproduces the committed
binary bit for bit before this change. Windows x86-64 and Android ARM64
libraries were rebuilt with the recorded toolchains; Android was not run on a
device.

## Original comparison

Not run under Wine. Results are unchanged by construction and are checked
against the interpreter, which already models the original builtins (group
evaluator `0x4b5b00`, `UnitSee`/`GroupSee` `0x5d`/`0x5e`, `IsDead` `0x64`) and
whose original comparisons are recorded with those implementations. An
internal evaluation speed-up has no observable original counterpart.

## Remaining candidates

Not changed here: AI perception refreshes (1.8 ms/tick, already partly native),
the per-frame danger flag in the worker, per-frame unit presentation callbacks
in a process that never draws, and grass streaming in the headless worker.
Each affects authority state or animation timing in ways that need their own
parity evidence.
