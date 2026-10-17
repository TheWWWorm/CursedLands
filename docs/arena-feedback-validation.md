# Autochess preview validation

17 October 2026. Source branch `fix/arena-feedback-20261017`, based on published
v1.9.0 (`55f47c688ae5c7e9e186058e480b11c4e74d2f5d`). This is an unreleased local
preview. Published tags, platform packages and the hosted browser were not changed.

## Mechanics

| Suite | Result |
| --- | --- |
| Recruitment | 676 checks, including 20 native fights |
| Preparation/result flow | 234 checks |
| Automatic purchase deployment and original sound resources | 16 checks |
| Company levels, shop odds and alliances | 448 checks |
| Expedition economy and migrations | 215 checks |
| Formation movement | 20 checks |
| Ten-player mode | 153 checks; full game reached elimination after 134 native fights |
| Identical opposing armies and alliance bonuses | 10 checks |

The ten-player checks cover seeded companies and pairings, creep/player rounds,
odd-player copied armies (including a copy of the human), damage, single payment,
terminal places, interrupted-fight recovery, malformed saves and independent mode
files. A synthetic 46-round game also checks late XP and bounded CPU histories.
Background combat leaves the global clock alone. The new mode uses real native
battles for the CPU-versus-CPU boards as well as the human board.

## Interface and persistence

Rendered tests used the copied production Linux engine with the new pack, Vulkan
Forward+, and a private X display. English 1280×800, Russian/German 1024×768 and
English 3840×2160 passed. Captures were visually inspected. Tests exercise actual
pointer/key input, purchase placement, Escape dismissal, equal shop/reserve card
sizes, sounds, the XP ring, complete left-side evolution notices, speed toggling,
mode switching, separate saves, standings, scouting and modal bounds.

The final German run includes 50 checks and confirms the result panel hides the
standings. The Russian run includes 48 checks and explicit board teardown. Earlier
English/4K passes each include 47 checks. The existing continuity suite passes
89 checks. All rendered test loggers report no scene/script errors. Early isolated
starts report an unavailable shader-cache folder before the fixture logger; the
preview launcher supplies dedicated XDG data/config/cache directories.

Two fresh processes verified 2× then 1× from saved settings. Neither new runs nor
loading either mode changes that preference. A copied version-seven player save
resumed at wave five with its army/capacity retained. Nine checks and screenshots
cover its expanded seed/resume layout in all three languages. The source player
save is untouched.

Translation scan: 2,455 entries, 141 dynamic wiki keys, 126 dynamic arena keys,
zero missing translations or format mismatches. `git diff --check` passes.

## Reproduction and limits

The task directory contains `run-preview.sh`, `runtime/`, `play-data/` and `qa/`.
The launcher opens the mode selection and keeps settings/saves in `play-data/`.
`qa/receipt.json` collects suite results; the logs and PNGs retain individual
checks. `runtime/SHA256SUMS` identifies the tested local engine and pack.

Headless suites run with `CursedLands.x86_64 --headless --render-thread safe --
--ei-path=<original data> --tool=<absolute path to tools/tests/arena_tournament.gd>`
and an isolated `XDG_DATA_HOME`. The rendered fixture is
`tools/tests/arena_feedback_ui.gd` with `--arena-resolution=de,1024,768` and the
corresponding original localized archives. Preferences use the same fixture data
with `--arena-preferences=2:1`, followed by a new process using `1:2`.

This turn validates Linux; other desktop platforms, Android and the browser were
not rebuilt or tested. CPU strategy has limited seed/balance coverage. The full
native run is a mechanics regression, not a claim about human win rate.
