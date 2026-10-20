# Public wiki map feature parity — 2026-10-20

The 1.19.0 game added creature-name filtering and creature-to-map highlights
in the native wiki. The public site still served the preceding map interface;
its live files matched the committed public export. This was a missing web
implementation, not a stale client cache.

## Scope

- Localized creature filtering leaves enabled exit and quest markers intact.
- Creature article links enable and highlight the corresponding authored map
  positions. Highlighted groups never include unrelated creatures.
- Search and layer choices persist in the map URL, through Back and reload.
- Native game binaries and published release archives are unchanged.
- The existing article export is still 1.10.0. Previous packaging had relabeled
  its six index files as 1.19.0; restoring 1.10.0 exactly matches their original
  manifest hashes. The interface version is recorded separately. No article
  text, original map positions, statistics or illustrations were changed.

## Checks

`tools/tests/wiki_map_browser.mjs` passed 143 checks with isolated Chromium
at 1440×1000 and 390×844, in English, Russian and German, for both campaigns.
The prior frontend from `50fd5b06` reproduced the missing control. Installing
this release's actual game service worker and then reloading the new wiki
verified that the new controls load normally and local storage survives.
These are desktop Chromium viewport tests, not physical-device tests.

`tools/tests/wiki_package.py` verifies that publishing rejects stale frontend
copies, changed files, incomplete campaign/language indexes, and invented
article versions. The real package check validated all 13,525 files.
JavaScript syntax and Git whitespace checks passed. The Impeccable detector
reported existing palette/type-ramp advisories and existing header/tab styling;
the established field-guide design was preserved. Highlight markers use the
existing brass, ink and reading-surface colors.

See `local.json` for individual checks and the adjacent desktop/phone captures.
