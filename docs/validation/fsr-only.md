# FSR-only preview validation

The preview is based on public commit `c99dbba8` and stable `v1.19.0`.
The standalone engine patch applies after the sixteen common Godot patches;
all 26 changed files reproduce byte-for-byte from that baseline.

The source contains only the AMD SDK integration. The packaging helper checks
both source snapshots and the template before exporting. Runtime absence checks
and final package checks are recorded after the Windows template finishes.

Linux stock-engine attribution tests passed 222 checks with zero failures,
covering English, Russian and German at 800×600 and 1280×720. The official
transparent AMD lockups are centered and legible, with no background boxes.
The credits retain their original scrolling and Escape behavior.
The approved master icon is unchanged. Translation checks report 2,873 entries
and zero errors, including dynamically selected FSR options, help and errors.

All execution tests use an isolated profile with a free cursor, FPS visible,
and all audio volumes zero. Native Windows and FSR 4 on compatible AMD hardware
remain unqualified. The stock-engine settings fixture also passed 130 checks, including all three
languages at 800×600, unsupported requests, help wrapping and fresh defaults.
Windows runtime results will be recorded separately.
