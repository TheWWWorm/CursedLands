# Game-file selector redesign: earlier iteration

This record documents the first redesign, which was superseded when the user
requested the approved logo and untextured buttons. The blank stone-and-bronze
plate was generated with `image_gen`; its prompt and provenance are retained in
`original-stone-button.provenance.json`. Its screenshots and results below are
historical evidence, not the current selector design.

The `before-first-run.png` capture is the actual desktop first-run screen before
the change at the GPU Lab display's 2880×1800 resolution. The other captures
come from the actual desktop and portable setup controls rendered in isolated
subviewports at the named resolutions. They include EN/RU/DE, 4K, 1440p, a
narrow portrait layout, and the expansion's ISO action. The first-run captures
have no original UI artwork loaded, which is the state before importing data.

`game_files_presentation` passed 849 checks with the real base-game archives
available to the test harness. It covers first-run layout without archive art,
all three languages at 390×844, 960×540, 1280×720, 2560×1440 and 3840×2160,
live resizing and scrolling, campaign selection, ISO visibility, installed
and missing data, busy/error states, Options return and opening the real game
folder. `first_import_dialog` passed 47 existing first-import and touch-dialog
checks. `menu_utility_glyphs` completed 303 checks with zero failures. Its
normal runner result reported a missing start marker because the GPU Lab CLI
returned only the last 64 KiB of its verbose output. The complete GPU Lab
stdout, stderr and job record are retained here; the unchanged regression
runner's `verdict` was applied to those full logs and passed, as recorded in
`menu-utility-full-verdict.json`.

All runs used isolated profiles with free cursor, visible FPS and muted audio.
Translation coverage passed with zero errors. The portable screen was exercised
on Linux at portable viewport sizes and its browser progress/error callbacks
were simulated; native Android and an actual web export/file picker were not
run in this validation. This setup screen is a remake feature, so there is no
original-game file-selection screen to compare under Wine.

The adjacent menu regression's unique visual outputs are in
`menu-utility-visuals/`; byte-identical natural/refreshed captures are mapped
in `duplicates.json`. The first-import dialog captures are also retained.
