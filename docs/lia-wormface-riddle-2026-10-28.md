# LiA Wormfaces' Riddle fix — 2026-10-28

Fix branch `fix/lia-wormface-riddle` (from local main `cccf554c`), commit
`411e4040`, worktree `local/scratchpad/lia-zhezl-kel/repo` (the only remaining
item in that scratch folder). Not merged into local main or pushed yet.

Retained:
- `local/validation/lia-wormface-riddle-20261028/` (~2 MB): native LiA 1.02
  screenshots/decoded quicksaves, probe tools and key sequences, gameplay
  reports and logs, the supplied stuck save (`save49`, gzip). See its README.
- `local/scratchpad/lia-zhezl-kel/repo`: worktree of the fix branch, kept until
  it is merged into local main; retire it with `git worktree remove`.

Removed after copying results:
- Native suite `local/runtime/sessions/lia-riddle-20261028` (627 MB: prefix
  copied from `templates/original-lia-1.02`, thin game directory, quicksaves)
  and its lock file. No Wine processes were running for it.
- Gameplay run directories `run-*` and `trial/` (~2 GB of staged runtimes and
  profiles; reports, selections and gzipped program logs were copied to the
  evidence `runs/` first), the rendered in-game check's staged runtime and
  profile (`ingame/`, 231 MB, with a played copy of `save49`; screenshots are
  retained as JPEG), the extracted copy of the supplied save archive (65 MB; the
  archive itself remains in the user's Downloads), map script text dumps
  (`work/`), scratch probes (`tools/`, `native/`, copied to `probe-tools/` and
  `native/`) and the memory-investigation directory (`mem/`; traces, probe and
  unfixed log copied to `runs/memory/`).

## Test memory

Parallel gameplay runs filled the 64 GB workstation: frozen LiA fixtures kept
every visited map loaded (up to 13 GB per process). Fixed in the branch by
`tools/tests/world_release.gd`. The runner now defaults to `--jobs auto`
(CPU threads and free memory, with a free-memory gate); on this machine that
chose seven jobs, peaking at 22 GB in total. Branches without the fix should
still be run with `--jobs 4` or fewer.

## Template finding

`templates/original-lia-1.02` did not boot as copied: Wine reported that it
could not load `kernel32.dll` (the seed lacks Wine's generated system files,
which no cleanup ledger row restores), and the game asked for disc 2 (the seed
lacks the LiA “Add-on” HKCU settings and the `C:\lia` link). The session copy
was repaired by copying missing files from a freshly initialized Wine 11.20
prefix (`cp -rn`, then `wineboot -u`) and importing the Add-on keys from
`local/scratchpad/lia-kel-checkpoints-20261023/original/prefix/user.reg`
(retained as `probe-tools/addon.reg`). The template itself was not changed.

## All-quests order sweep (commit `8fcc434b`)

Scratch `local/scratchpad/lia-all-quests/` (581 MB) was removed after its
evidence was copied to
`local/validation/lia-wormface-riddle-20261028/runs/all-quests/` (1.3 MB:
reports, runner logs, gzipped shard and probe logs, quest inventory and the
inventory, dump and probe scripts). Removed:

- four runner outputs (`run-sweep-01..03`, `run-unfixed-02`; runtimes and
  per-shard profiles, about 520 MB);
- the unfixed `game/` copy (59 MB, reproducible from `411e4040^`);
- the probe and dump profiles;
- map script dumps (reproducible from LiA 1.02 with `dump_maps.py`).

No process was using the folder. Import side effects in the worktree (three
`.import` files, ten generated `.uid` files, `game/.godot`, 14 MB) were
reverted or removed before the commit.

Observed: sweep-03 ran its 12 shards one at a time (66 minutes rather than
13). The runner's free-memory gate held them back while other workloads on the
machine held memory. This is inferred from per-shard finish times and is not
a test defect.

## Merge into local main (`f93d6e74`)

Verification output `local/scratchpad/merge-lia-main-20261028/` was removed
after its report and runner log were copied to
`local/validation/lia-wormface-riddle-20261028/runs/merged-main-f93d6e74/`
(79/79 passed). The local main checkout was left with only the other session's
uncommitted `docs/wine-proton-workflow.md`. Nothing was pushed.
