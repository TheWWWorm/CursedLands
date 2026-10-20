# FSR-only preview validation

The preview is based on public commit `c99dbba8` and stable `v1.19.0`.
Game source: `b6823be66c3346afd9014c6f1fca74f15d693a1f`.
The standalone engine patch applies after the sixteen common Godot patches;
all 26 changed files reproduce byte-for-byte from that baseline. The Windows
release template rebuilt successfully with `use_fsr_sdk=yes`.

| Check | Assertions | Failures |
| --- | ---: | ---: |
| Stock Linux engine: attribution and layout | 222 | 0 |
| Stock Linux engine: settings and fallback | 130 | 0 |
| Exported Windows engine: attribution and isolation | 224 | 0 |
| Windows rendering, motion, resize and shutdown | 103 | 0 |
| Campaign frame-generation gates | 47 | 0 |
| Missing AMD runtime: localized UI and fallback | 132 | 0 |

Windows tests ran through Wine 9 / VKD3D-Proton 3.0.1 on an RTX 3090,
using the Safe rendering thread. Native Windows execution and FSR 4 on
compatible AMD hardware remain unqualified. Each process exited cleanly;
there were no script or native errors.

The actual providers were SR 3.1.5 and FG 3.1.6. All four upscaling modes
executed SDK dispatches. For both moving-camera and resized-window samples,
120 rendered frames produced 120 generated frames and 240 DXGI presents.
During real campaign gameplay, 90 rendered frames produced 90 generated
frames and 180 presents. Pausing, loading, opening the menu and disabling
upscaling stopped generated frames; resuming gameplay restored them.
DXGI presents do not measure physical monitor scanout. Screenshots show
rendered frames, not interpolated frames.

The packaged splash and credits passed English, Russian and German checks at
800×600 and 1280×720. Visual inspection confirmed centered, legible official
AMD lockups, original aspect ratios and transparent backgrounds. The approved
master icon is unchanged; all six embedded Windows icon sizes match the
approved ICO. The ordinary splash and other platform branding remain unchanged.
Translation coverage reports 2,873 entries and zero errors, including dynamic
FSR labels, choices, help and capability messages.

Runtime checks confirm that the private SDK singleton, scaling enum, game
script, artwork and options are absent. Source checks exclude private history
and integrations. The packaging guard rejects the previous combined source
and native template. The package contains the three pinned AMD DLLs and
Agility runtime; SDK license notices are byte-identical to the originals.
The normal game native libraries are retained. All file hashes and the
Windows 1.20.0.4 version resource were verified.

All execution tests use an isolated profile with a free cursor, FPS visible,
and all three audio volumes zero. This work does not change player defaults.
Full results, limitations and binary hashes are in [the machine-readable
record](fsr-only.json); individual results and screenshots are in [fsr-only/](fsr-only/).
