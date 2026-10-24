# Contextual tutorials

Tutorial script events now make a short hint eligible instead of opening a
paused tutorial window. The field card uses the game's serif type, dark brown
panel and brass border. It occupies about 320 by 60–100 logical pixels, depending
on language and input prompts. Shop hints scale with the surrounding interface.

## Presentation and timing

- One automatic card at a time, with one action to try. The card body lets
  gameplay clicks through and never captures focus, controller routing or pause.
- Nine seconds of display, including a 0.45-second fade, then an eight-second
  quiet period. Performing a recognized action can dismiss the card sooner.
- Movement, camera orbit/zoom, attacks, stance and movement-mode changes retire
  their corresponding hints. Healing retires when the wounded hero recovers or
  the suggested spell is no longer usable.
- Combat, conversations, cutscenes, loading and other open screens suppress field
  hints. Only the latest pending request is retained; requests expire after 24
  seconds, including time spent in a conversation. Encountered topics remain in
  the guide even if their card was superseded.
- Explicit **Read more** has no timeout. The full guide uses the existing wiki
  menu behavior: single player pauses when the player opens it; co-op continues.

The healing lesson requires observed damage to a locally controlled hero during
the current fight, an opponent defeated, at least 2.5 seconds out of combat, and
remaining wounds. The selected hero must have an equipped, usable healing spell
and sufficient stamina. Old wounds alone, another player's wounds, or merely
crossing the original tutorial trigger do not qualify.

The relevant visible control receives a slow gold outline. Healing resolves the
actual equipped spell slot; other cues target movement, time, map, message log,
character status, actions, weapons, belt, party portraits and construction slots.
Closed panels point to their opening control. Each automatic appearance plays
the original tutorial cue once, respecting the sound-effects volume. Manually
reopening help stays silent.

## Help and input

**H** (or the rebound tutorial key) expands the current or most recent field
hint. The book button opens the in-game guide. With a gamepad, open the game
wheel and choose **Help**, **Guide**, or **Hide hint**. The default wheel binding
is RT in tactical mode, or LT+RT in direct control. Screen help is also available
through the gamepad's system action. Prompts use the current bindings and update
when the active device changes; the hint itself never takes over navigation.

**Getting started** contains concise lessons and the installed edition's original
tutorial reference. **Recent hints** restores topics encountered in the current
campaign. The base game has 36 substantive topics and 78 original reference
pages. Context-specific lessons become available after their encounter; the
empty `lmp` placeholder is excluded. Unknown installed/mod tutorial text remains
readable without displaying internal IDs. Original pages are labelled as classic
controls so they are distinguishable from current bindings.

All new copy, settings labels and help are supplied in English, Russian and
German. Original reference pages come from the installed localized archives.
The standalone wiki exporter includes general guide articles but never local
history. The web home entry appears when those articles are present in its data.
This source change does not publish new website data or a game release.

## Persistence and maintenance

`TutorialProgress` stores campaign-local encounter, shown, acted, read and
dismissed flags in `user://tutorial_progress.cfg`. Existing `tutorial.ini` entries
migrate as encountered/shown, preventing repeats without claiming mastery. No
learning history enters savegame or multiplayer packets. Disabling **Contextual
hints** keeps the guide and encounter history available.

`TutorialGuide` owns topic copy and archive parsing; `TutorialContext` observes
local results without issuing commands; `TutorialPanel` owns presentation and
live control anchors. Extend these together when introducing a lesson.

## Validation

Run `tools/tests/contextual_tutorials.gd` with the game's normal `--tool` launcher
and installed base-game data. Use an isolated development profile with a free
cursor, FPS shown and all audio volumes zero. CPU behavior checks work headless.
Rendered checks must run through GPU Lab with automatic GPU assignment,
`--display-driver x11 --audio-driver Dummy --max-fps 30`.

The rendered suite covers EN/RU/DE, keyboard/mouse and simulated gamepad input at
800×600, 1280×720, 1920×1080, 2560×1080 and 600×960, plus native shop and guide
navigation. It checks control anchors, dismissal, post-combat eligibility,
remapping, nonblocking input and preservation of the original reference pages.
The sound check verifies the existing asset and one-shot dispatch while tests
remain muted. These are prepared game contexts, not a physical-controller or
novice playtest. Archive prose follows the edition used for the test.

`tools/tests/tutorial_wiki_export.gd --guide-output=/absolute/private/fixture.json`
exports a private fixture using the production catalog. Run
`tools/tests/tutorial_wiki.mjs --public=/absolute/repo/public
--fixture=/absolute/private/fixture.json --output=/absolute/private/results
--chrome=/absolute/chromium` under GPU Lab, with Playwright available. It checks
the current standalone interface against fresh guide data in all three languages,
including browser Back/reload. No live site is modified.

Also run `python3 tools/check_translations.py`,
`python3 tools/prepare_public_wiki.py --check --output public/wiki`, and
`git diff --check`.
