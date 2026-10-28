# AI nearby-unit list order — 2026-10-28

Every AI unit keeps a list of the units in the 16 m grid cells around it. It
is rebuilt every 8–11 AI ticks, and the perception scan, the ally list for
helpful spells and the witness checks read it. The remake built it in
registry order (`GameWorld` unit rows). The original builds it in a different
order. The scan's comparisons were already identical; only the order differed.

**Result: fixed.** `GameWorld.notice_units_near` (used by
`UnitAI._notice_candidates` and by `GameSound._near_units`) now returns the
original order, and a new comparison kind runs the original list refresh.

## Original behaviour (GOG English `game.exe`, SHA-256 `d0fc0bb2…0ad8`)

Read from the Ghidra decompile and disassembly and then run in the Unicorn
replay below:

* **Refresh 0x5ca1d0.** When its countdown (perception state +0x20) falls
  below 1 it draws `(rand() & 3) + 8` again, clears the list (state +0x28 head,
  +0x2c tail), looks up the cell offsets for `max(sight × factor, life) × 2 / 32`
  (0x5bfc40) and visits them in table order. For each cell (0x5c0930: cells of
  0x54 bytes, unit list at +0x20) it walks the units from head to tail, skips
  the observer, and **inserts each unit at the list head** (0x5ca37a–0x5ca3d0:
  `next = old head`, `prev = 0`, old head's `prev` = new node, head = new
  node). The finished list is therefore the reverse of the visiting order.
* **Cell table 0x5bf8f0.** It writes the 21 × 21 offsets (dy outer, dx inner,
  `dx` in the low word) with distance
  `D = √(max(|dx| − 1, 0)² + max(|dy| − 1, 0)²)`, then sorts them with the CRT
  `qsort` 0x6e88bc (comparator 0x5bfc10). That sort is not stable, so cells of
  equal `D` are in qsort's order: the nine `D = 0` cells come as
  (0,0) (1,0) (1,1) (0,1) (−1,1) (−1,0) (1,−1) (0,−1) (−1,−1). The table was
  read from the replay (`NOTICE_CELL_ORDER` in `ai.gd`). The prefix counts
  (9, 21, 25, 37, …) agree with the remake's existing cell-set selection.
* **Cell lists.** Placement 0x5c0df0 appends the unit at its cell's list
  tail (0x5c0ebe–0x5c0efc). A move (0x5c11d0) removes the unit from its old
  cell (0x5c1470) and appends it to the new cell's tail only when the cell
  changes. Within a cell, units are in order of arrival.
* **Consumer 0x5ca5a0** walks the list from head to tail. A newly noticed
  living unit is pushed at the head of the noticed list (0x5ca8f8). Corpses
  go to the corpse lists through 0x5cd500.

So the list starts with the latest arrival in the last cell of the table and
ends with the first arrival in the observer's own cell. Head insertion is one
of three parts of the order; the cell table order and arrival order inside a
cell are the other two.

## Remake change

* `UnitAI.NOTICE_CELL_ORDER` holds the original table. `notice_cell_rank()`
  gives an offset's position in it.
* `GameWorld.notice_units_near` reorders its members. On the registered host
  path, the native helper reads the 16 m coarse buckets. At positive
  coordinates, each bucket is exactly one original cell, and `NavGrid.rebucket`
  appends a unit to a bucket only when it enters the bucket. That is the
  original arrival order. The buckets are put in table order and the whole list
  is reversed (`_bucket_list_order`). The script, client and unregistered paths
  use the unit's position in its bucket, or registry order if it has none
  (`_cell_list_order`). Membership is unchanged.

Effects in the remake:

* `player_perceive` scans in this order. This changes the insertion order of
  new noticed units, the order of the immediate `call_for_help` calls (for
  each helper, a later call replaces the earlier one) and the order of corpse
  suspicion.
* The `_friends` order for list-B spells changes. Seen-assault and
  seen-murder observers are also processed in this order, which affects the
  order of their forced refreshes and random draws.
* `GameSound._near_units` uses the list only for membership.

## Tests

* New `stealth/notice_candidate_order` (`tools/tests/notice_candidate_order.gd`,
  registered in `tools/parity/gameplay_catalog.json`). It checks the table,
  then the list order for a 12-unit layout: several cells, two arrivals in one
  cell, a unit moving into the observer's cell, a death, leaving and returning
  to a cell, and removal. It checks the native-helper, script and exhaustive
  paths, plus `UnitAI._notice_candidates`. Fixed: **454 checks, 0 failed**.
  Unfixed (`git archive` of `8c54bfa5`): the table checks could not run, and
  12 checks ran with 11 failures, including every list-order check (the list
  came back in registry order `A B C … J`). The expected orders are the ones
  the native replay produced for the same layout (`mixed_cells` below).
* New comparison kind `perception_candidates` in the
  [perception-trigger family](../original-parity-perception-triggers.md). It
  runs the original refresh, cell table, placement and moves. Fixed: **19 of 19
  match**. Unfixed: **0 of 19 match** (first difference in every scenario is
  the candidate order). The whole `perception_` family now gives
  **469 match, 2 differ**. The 2 are the known peripheral-vision-through-a-
  blocked-ray difference (group D).
* Python unit tests `test_ext_perception_triggers`, `test_extensions` and
  `test_harness`: 40 tests passed, including a native sensitivity test showing
  that arrival order changes the native candidate order.
* Related gameplay programs (headless, 4 jobs): 31 programs passed, with
  20,646 checks and 0 failures. They cover AI activity and eligibility,
  reaction recipients, the `stealth` category, combat inputs, peasant help
  (both campaigns), registry queries, the Suslanger and prison-alarm quest
  programs of both campaigns, corpse-memory saves and arena combat
  decisions. That run used the source before a rename-only change (table
  and helper names). On the final source, `notice_candidate_order`,
  `perception_batch` and `registry_queries` were run again: 454 + 2,857 +
  1,283 checks, 0 failed. The perception comparison family was also run
  again (469 / 2). The unregistered `script_perception` (7 checks),
  `pack_alert_recovery` (14) and `spell_alert_encounter` (8) passed with no
  failures.
* Cost: 2,000 queries of about 290 units with the native helper took about
  128 µs per query fixed and 115 µs unfixed. These figures were measured while
  other tests were running. The list is rebuilt once every 8–11 ticks per
  unit.

## Not compared / uncertain

* **No Wine run.** The list is internal state that the original never shows,
  and reading it under Wine would need a debugger. Instead the replay runs the
  original instructions of the refresh, the table build, placement and moves.
  The supplied inputs are the occupancy stamp 0x5b6a80 (success), `rand`, the
  map record and the arrival order.
* The arrival order in real play depends on when each game moves units
  between cells: spawn and load order, and per-step movement. The remake
  rebuckets on every position change. Whether its event order matches the
  original during play was not compared.
* The original noticed list puts new entries at its head. The remake's
  `noticed` dictionary appends them, and that is unchanged. The remake's
  readers sort the list (`enemies`, `_player_target`) or test membership.
* The remake calls `call_for_help` inside the scan. Where the original raises
  its help call, and in which order, was not traced. The order of the
  witness loops in the original was not checked either.
* No check was made of whether the original's death path re-files a unit in
  its cell. The remake keeps a dead unit in its bucket.
