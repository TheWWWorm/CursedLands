# Wine and Proton development workflow

This is the workstation workflow for the original Evil Islands base game,
Lost in Astral (LiA), and Windows Cursed Lands tests. It also applies when a task
uses an old test harness. Follow the current GPU Lab rules in `AGENTS.md` rather
than the fixed displays or per-test prefix copies in historical scripts.

## Reuse installations; bound the writable state

- Keep one verified installation of each required Wine/Proton version. The
  runtime itself is shared read-only; do not download or unpack it per issue,
  language, renderer, test case, or release.
- Keep separate reference data and seed prefixes for the original base game,
  patched LiA, and the remake renderer configurations. Never boot or modify a
  seed prefix. Never point tests at a player's prefix or saves.
- Use one writable prefix per concurrently running suite, reusing it for serial
  cases. Use an exclusive lock for the entire Wine session, including startup,
  subprocesses, and shutdown. Concurrent suites must have separate prefixes and
  separate writable game/save directories. Do not run Wine and Proton against
  the same writable prefix, or upgrade its runtime version in place.
- A clean-prefix test may create an additional temporary prefix when isolation
  is the behavior under test. Document that reason and remove it afterwards.
  Do not make a complete prefix for every screenshot, case, or benchmark sample.
- When a seed is copied for a suite, omit generated shader caches and crash
  dumps. Reset only the suite's mutable application state between independent
  cases; explicitly seed required saves and settings. Keep cold-cache and
  warm-cache measurements distinct, with an explicit warm-up step.
- Do not hardlink writable prefixes, registry files, DLL overrides, game
  executables being patched, or saves. In-place writes would cross-contaminate
  tests. Symlink only reference assets/toolchains treated as read-only; copy
  the small files that the test must modify.

On this workstation, `/home/llm2x/Documents/EI/local/runtime/` provides stable
entry points. Its links retain the existing qualified files without duplicating
or relocating them. Check the resolved path before any future cleanup. The
`sessions/` directory is for bounded writable suites and `locks/` for their
exclusive lock files. Do not allocate a new permanent prefix for each task.

| Entry under `local/runtime/` | Purpose |
| --- | --- |
| `toolchains/wine-11.20` | Existing Wine 11.20 WoW64 runtime used for native original-game checks |
| `toolchains/proton-ge-11-11` | Existing GE-Proton11-11 distribution for the established remake DX12 workflow |
| `toolchains/wine-dx12-support` | Existing support libraries used by the Windows renderer harnesses |
| `templates/original-base` | Retained base-game Wine seed; do not run it directly |
| `templates/original-lia-1.02` | Retained patched-LiA seed; do not run it directly |
| `templates/remake-dx12` | Retained Wine/DX12 seed |
| `templates/remake-proton` | Retained seed used with the Proton renderer harness |
| `reference/base` | Original extracted base-game assets and executable |
| `reference/lia-disc` | Original LiA disc extraction, before applying the official patches |
| `reference/lia-1.02` | LiA reference assembled with official 1.01 then 1.02 patches |
| `reference/lia-cd2` | Retained LiA second-disc mapping used by the qualified prefix |

The runtime versions and reference executable hashes were checked on 2026-10-26.
The graphical qualification comes from the existing comparison records, not a
new graphical run during workspace cleanup. A runtime, driver, patch, or renderer
change requires an appropriate fresh comparison before calling it qualified.

## Original base game

Use `toolchains/wine-11.20/bin/wine` and the base seed. No system `wine` command
was found during the inventory; use the explicit runtime path. Preserve its
WoW64 configuration rather than forcing a different `WINEARCH` on an existing
prefix.

Create one thin, writable game sandbox for the suite. Copy the executable,
configuration, and required seed saves; reference the large original resource
directories from `reference/base`. Run with the sandbox as the working directory
so relative resources, configuration, and saves resolve there. Never write through
an asset link into the reference extraction. Copy an asset first if a test needs
to modify it.

The retained native setup is documented by
`local/scratchpad/outstanding-issues-20261023/run_original.py` in the workspace.
Use it as configuration evidence: it sets the native registry, DirectX version
keys, Wine's GL renderer, a null ALSA configuration, and a windowed virtual desktop.
Do not run that historical script unchanged: it owns old paths and state.

The verified base `game.exe` SHA-256 is
`d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8`.
The corresponding source is `inspection/extracted/app/game.exe`.

## Original Lost in Astral

Use the same shared Wine installation with a separate LiA seed and writable
game sandbox. Use the patched `reference/lia-1.02` data for patched-game parity.
Do not silently substitute the unpatched disc extraction or the base game's
executable. Preserve the verified patch order: official 1.01, then 1.02.

The reference assembly and patch hashes are recorded in
`local/scratchpad/lia-official-patches-20261023/patched-game-manifest.json`;
the native session, save checks, and settings are recorded in
`local/scratchpad/lia-kel-checkpoints-20261023/original/session-provenance.json`.
Both paths are relative to the workspace, not this Git checkout. Preserve their
referenced patch payloads, resource links, and media mappings. Inspect
`dosdevices` after creating the suite prefix; never replace a required media
mapping with an unrelated installation or a physical device guess.
The retained LiA seed has `dosdevices/e:` pointing relatively to `../../cd2`.
After copying that seed elsewhere, explicitly remap `e:` to the absolute resolved
`local/runtime/reference/lia-cd2` target; do not leave the relocated relative link
pointing at a nonexistent or different directory.

The patched LiA `game.exe` SHA-256 is
`9ecd475f5776681b8ffe1a8bb05cf67fe7adcceb62d0949135261ed7d3616c12`.
The base executable is used by the existing save decoder for verified decoder
routines; that does not make it the LiA runtime executable.

Preserve original before/after saves and decoded reports outside disposable
runtime state. The native checkpoint workflow enables `thingamabob` after each
process restart and verifies a fresh `cp_capture_nonce` in a decoded save before
accepting console-driven evidence. Historical capture helpers hardcode a display;
adapt them to the assigned GPU Lab job rather than reusing that display number.

## Proton and remake Windows tests

Reuse `toolchains/proton-ge-11-11`. The existing standalone renderer workflow
invokes its `files/bin/wine`, with its own `files/lib` and
`files/lib/x86_64-linux-gnu` libraries and an explicit suite `WINEPREFIX`.
Use the matching `files/bin/wineserver` for that prefix. A Steam-style Proton
launcher uses a different compatibility-data setup; do not mix those layouts
or pass one of their prefixes blindly to the other launcher.

The retained setup recipe is
`local/scratchpad/release-1.30.0-20261025/release/runtime_harness.py`. It documents
the native DX12/DXVK/NVAPI overrides, support DLLs, and adapter capture used for
that release. Reuse the setup once per suite; its old per-tag `copytree(PREFIX, ...)`
pattern must not be copied into new work. Keep runtime and driver identity,
overrides, executable/PCK hashes, and renderer with each result.

For base and LiA remake comparisons, keep separate application profiles and
pass the intended data root explicitly (`--ei-path=Z:/absolute/path` for Windows).
Use the data version required by the test and record it; the native LiA 1.02
reference and the remake's disc-input fixture are different inputs. Inspect
the actual Wine user directory: Proton commonly uses `steamuser`, while older
Wine profiles here use `llm2x`. Do not save results into the wrong profile.

The current Proton entry point resolves into a historical scratchpad directory.
Only that standard runtime subtree is a shared dependency. Sibling withdrawn
RTX 30 / `dlssg_for_sm86` packages are not reusable dependencies and must never
be packaged, restored into distributions, or published. Do not carry historical
GPU-identity or capability-spoofing environment overrides into normal tests.

## GPU Lab and session lifecycle

Run graphical Wine, Proton, DXVK, and VKD3D work through GPU Lab with `gpu=auto`
and an absolute working directory. Do not create Xorg/Xvfb, select a historical
display, change monitor configuration, or override GPU Lab's display/GPU variables.
Native Win32 runs do not take Godot's `--display-driver` argument. Godot remake
inspections use `--audio-driver Dummy`, `--max-fps 30`, and X11 where applicable.

Before launching a test profile, ensure `confine_mouse=0`, `show_fps=1`, and all
three `volume_sfx`, `volume_stream`, and `volume_voice` values are zero. Original
native games also need the matching `AudioSFX`, `AudioStreaming`, and `AudioSpeech`
registry settings and the recorded null-audio setup. Keep these settings in the
isolated suite, not player defaults or the reference seeds.

A suite wrapper should perform the following inside the assigned GPU Lab job:

1. Acquire an exclusive prefix lock, validate the runtime/seed/data identity,
   and refuse a prefix marked `RETIRED-BY-CLEANUP.md`.
2. Initialize its writable prefix once if needed, prepare the thin writable
   game directory/application profile, and apply the test settings.
3. Run the suite serially in that prefix, resetting only the required per-case
   state. Keep result directories limited to logs, measurements, screenshots,
   fixtures, hashes, and explicit before/after saves.
4. In a `finally`/exit cleanup path, stop only that prefix's Wine server using
   the matching runtime, and wait for it to exit. Do not use global `killall`.
5. Preserve useful evidence and any unique edits/saves, then remove the disposable
   prefix, stage, and caches. If keeping a bounded reusable session instead,
   register its path, owner/purpose, runtime version, and retention reason in the
   workspace map. Report retained large files and space reclaimed.

Do not preserve hundreds of complete Windows installations as test evidence.
The 2026-10-26 cleanup retains old profile paths and unique files, removes only
verified duplicate system files from selected finished test prefixes, and records
their retained sources and hashes in `local/maintenance/2026-10-26-cleanup/`.
Marked prefixes are historical evidence, not ready-to-run seeds. Restore them
from their deletion manifest before deliberate reuse; ordinarily start the next
suite from a registered template instead. Removed shader caches are regenerated
by a new warm-up run.

### Restoring a deliberately retained historical prefix

Use `wine-file-removals.jsonl.gz` in the dated cleanup directory as the record
of files actually removed. It retains the preflight hashes, original metadata,
and matching source paths; duplicate planning files were consolidated only after
an exact comparison with this authoritative removal ledger.

1. Select rows whose `prefix` exactly equals the historical prefix's absolute
   path. Stop its matching runtime and acquire the prefix lock first.
2. For every row, verify that its retained `source` exists and its SHA-256 equals
   `sha256`. If any source differs or is missing, stop; do not substitute a DLL
   from a different version.
3. Copy the verified source bytes to the recorded missing `path`, restoring the
   recorded `mode` and `mtime_ns`. Use real copies, not symlinks or hardlinks.
   Never overwrite a file that has since been created or modified without
   comparing it and preserving that work.
4. Verify the restored files against the recorded hashes and confirm every
   removed file for that prefix has been restored before removing its marker.
   User data, registry state, and unmatched system files were kept at their
   original paths. Generated shader caches will need a fresh warm-up.

The retained runtime/template sources named by this ledger are dependencies of
the historical evidence. Preserve them until the affected prefixes are explicitly
discarded or their recoverable state is migrated and revalidated.
