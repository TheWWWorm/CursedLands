# Autochess preview validation

17 October 2026. Branch `fix/arena-feedback-20261017` includes published
v1.10.0 (`a49330496ce0d26b07885ac320ee057380908d7f`) through `origin/main`
(`2da3e23cee9fbb542b318a0d1637b383a3909e68`). The earlier preview used v1.9.0;
the results below supersede that validation. This remains an unreleased local
preview. Published tags and release artifacts are unchanged.

## Mechanics

| Suite | Current result |
| --- | --- |
| Nine-player tournament | 145 checks, 161 native fights through elimination |
| Battle limits and frog duel | 9 checks |
| Current armor, training and reward balance | 23 checks |
| Purchase deployment and sound resources | 16 checks |
| Shopping during native combat | 72 checks |
| Opposing alliance bonuses and arrival timing | 12 checks |

The tournament checks cover the human plus eight CPUs, independent company
budgets, random preannounced pairings, creep rounds, odd-player copies,
elimination, all live home battles, idempotent settlement, separate mode saves,
interrupted fights, malformed-save rejection and migration of the old ten-seat
preview without losing the human company. A synthetic 46-round game also checks
late XP and bounded CPU histories. The complete native game used one seed and
ended after 18 rounds; this tests mechanics, not human win rate or overall balance.

Combat uses v1.10.0's 80% armor absorption cap. The frog duel makes positive damage
and finishes; separate checks enforce the two-minute limit and a draw after ten
seconds without positive damage. A player-round draw removes ten health from
both owners. Ghost copies cannot damage their donor a second time. Purchases
during combat leave the current fighting figures and their alliance snapshot intact.

## Interface and persistence

The final gray palette and smaller player names passed 64 rendered checks each in
Russian at 1024×768, English at 1280×800 and German at 1920×1080. Tests used a copy
of the production Linux engine, Vulkan Forward+, a private X display and the
corresponding original localized archives. Captures were visually inspected.

Checks cover equal mode buttons; automatic deployment; Escape dismissal; original
reroll, rejection and level-up sounds; XP progress; every reserve slot fitting
without horizontal scrolling; matching shop/reserve heights; transparent shop,
reserve, alliance and standings surfaces; nonoverlapping round/list bounds;
preannounced opponents; live CPU purchases; all nine boards in a 3×3 map; clicking
a board to watch it; simultaneous native combat; immutable fighting snapshots;
and global pause. Names use 12-pixel type with 14-pixel health numbers. Snow-facing
text and icons use neutral dark gray (#242424); active tribes use dark copper.

The v1.10.0 shop/reward suite passed 168 rendered checks in Russian, including
original item artwork and automatic post-battle transitions. The main-menu suite
passed 14 checks, preserving the larger bottom utility buttons. A copied
version-eight expedition save resumed at wave five with four creatures; nine
checks cover its opening/resume layout in EN/RU/DE. The source save is untouched.

Two fresh processes verified the saved 2× preference, changed it to 1×, then
verified 1× and changed it back to 2×. New runs and either mode's loaded saves keep
the global preference. The alliance fixture was updated to use the live-board
adapter and checks that five enemy copies arrive at the bell before comparing
both armies' modifiers; zero-assertion results from the obsolete fixture are not
used as evidence.

Translation scan: 2,525 entries, 141 dynamic wiki keys, 129 dynamic arena keys,
zero missing translations or format mismatches. The editor import, pack export
and `git diff --check` pass. Rendered runs report no script errors. The private
X server reports an unavailable input method, which does not prevent pointer
or keyboard tests.

## Reproduction and limits

The task directory contains `run-preview.sh`, `runtime/`, `play-data/` and `qa/`.
The launcher opens the two-mode selection and isolates settings/saves in
`play-data/`. `qa/receipt.json` identifies the final logs and results;
`runtime/SHA256SUMS` identifies the tested pack and copied engine/libraries.
Older captures/logs remain as history and are not the final validation.

Run headless suites with `godot-4 --headless --render-thread safe --path game --
--ei-path=<original data> --tool=<absolute path to tools/tests/arena_tournament.gd>`
and an isolated `XDG_DATA_HOME`. The final rendered fixture is
`tools/tests/arena_latest_ui.gd` with `--arena-resolution=ru,1024,768`,
`en,1280,800` or `de,1920,1080`, using the corresponding original language data.
Preferences use `tools/tests/arena_preferences.gd` with
`--arena-preferences=2:1`, followed by a new process using `1:2`.

Validation covers Linux. Other desktop platforms, Android and the browser were
not rebuilt or tested in this change. CPU strategy has limited seed and balance
coverage.
