# Game-file selector: logo and flat controls

The desktop and portable game-file selectors use the approved transparent
`game/icon.png` logo above the title. All selector button states use flat Godot
styleboxes, with distinct selected, hover, focus and disabled states. No button
texture or generated background is used. Text remains native and the layout
scrolls within the safe area on small screens.

The registered `game_files_presentation` regression passed **1,170 checks** on
Linux with the Compatibility renderer. It checks both selector variants in
English, Russian and German at 390×844, 960×540, 1280×720, 2560×1440 and
3840×2160; verifies the approved logo, untextured button states and selection
contrast; and exercises live resizing, scrolling, campaign and ISO selection,
import busy/error states, Options return and opening an installed folder.
`first_import_dialog` passed **47 checks**. Translation coverage passed with
zero errors, and the regression-runner unit suite passed 11 tests.

Before the change, the expanded regression failed with 261 assertions covering
the missing logo and textured styles; its result and log are retained as a
negative control. Captures show the actual controls in isolated subviewports
without original UI archives. The test profile kept the cursor free, FPS on and
audio muted. Portable layouts were rendered on Linux and browser callbacks
simulated; native Android and an actual browser file picker were not tested.
The prior textured design and its related evidence remain documented in the
sibling `game-file-selector-2026-10-28` directory.
