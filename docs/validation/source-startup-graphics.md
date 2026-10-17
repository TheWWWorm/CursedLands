# Source startup graphics — 17 October 2026

The two errors visible in the 1.11.0 editor screenshot reproduce from stable
commit `f123ee28fc4eb90c0463595c637831e76e57647c` with official Godot and the
ordinary English GOG game data. The fixes remain local; no release, published
tag, hosted export, or installed game was changed.

## Shader compilation

GDScript preserves CRLF inside multiline string literals. A checkout produced
by `git -c core.autocrlf=true checkout-index` therefore puts CRLF in the embedded
shader programs. `Gfx.compose` previously replaced the exact LF-delimited pair
`varying vec3 ei_e;\nvarying float ei_k;` with the packed `ei_vertex_inputs`
declaration. That match failed on CRLF input, while the independent insertion
of `ei_vertex_inputs = vec4(0.0);` in `vertex()` still succeeded.

The real shader compiler then reports `Unknown identifier in expression:
'ei_vertex_inputs'`, exactly as in the screenshot. The regression reproduces
this for terrain, ordinary/enhanced water, moving/still foliage, map objects,
units, grass and ground-contact objects. These programs are used even when
optional graphics effects are disabled.

The fix normalizes CRLF before shader composition. `.gitattributes` also keeps
GDScript, shader and shader-include files at LF under Windows Git settings, so
earlier shader-fragment transformations receive consistent source too. A fresh
`core.autocrlf=true` checkout of all 349 tracked shader/GDScript files contains
no CR characters with this policy.

The player's later details identify Windows 10, a ThinkPad E15 Gen 2 and a
Russian Demoth repack. Windows line endings are a reproduced explanation of
the screenshot, but their actual checkout settings, GPU, Godot version and
rendering driver have not been supplied. No Demoth installation was tested.

## Graphics preset application

`GfxDetect._apply_live` walks the recursive snapshot returned by `find_children`.
Applying an earlier terrain's options can synchronously free reflection or
sector presentation nodes that still occur later in that snapshot. Evaluating
`n is EITerrain` on those entries raises `Left operand of 'is' is a previously
freed instance`, aborting the update before its final options notification.

The fix checks `is_instance_valid(n)` before the type test. The regression
covers a freed ordinary descendant, a freed terrain descendant, continued
updates to a later terrain, and exactly one final notification. It also loads
the real menu island and switches through tiers 0, 1, 2, 3, 4, 5, 0, 5. The old
code fails on real menu transitions to tiers 2 and 5; the fixed code completes.
Two real menu nodes expire during these transitions.

The soft-ground uniform-enumeration message in the screenshot is a performance
warning. `_prepare_material` already caches the shader identity and source and
refreshes that cache when variants change. It is separate from the two
reproduced errors; that code was not changed.

## Verification

Run from the repository root, substituting an owned game-data folder:

```sh
godot --headless --path game --editor --import
godot --path game --render-thread safe --rendering-method forward_plus -- \
  --ei-path="/path/to/Evil Islands" --tool="$PWD/tools/tests/shader_line_endings.gd"
godot --path game --render-thread safe --rendering-method forward_plus -- \
  --ei-path="/path/to/Evil Islands" --tool="$PWD/tools/tests/gfx_detect_live.gd" --calibrate-startup
python3 tools/check_translations.py
```

The shader suite compiles both LF and CRLF variants, compares uniform
interfaces, submits real draws, reads back the viewport and checks the error
logger. Forward+ also exercises both fog forms. The live suite optionally runs
the complete graphics calibration, verifies the persisted completed result
and closed progress overlay, and captures its final textured scene.

Results and exact engine/renderer commands are recorded in
`source-startup-graphics-2026-10-17.json`. Baseline failures are retained
separately from passing fixed runs. The full Windows-style source tree was
created before applying the LF policy; only the two patched implementation
files were replaced, retaining CRLF, to test existing checkouts too.

No player-facing strings or layouts changed. The translation scanner reports
2,563 entries and zero errors. The final calibration screenshot was visually
inspected: textured terrain and foliage are present and the result dialog is
readable.

Eight final safe-thread/headless runs pass 332 assertions with no shader or
script errors: official 4.7 headless, Forward+, Mobile and Compatibility, plus
the entire CRLF checkout on official 4.7.2 through real menu transitions and
completed calibration. Compatibility used Mesa llvmpipe; the Vulkan renderers
used the RTX 3090. The checkout-policy verification separately covers 349 files.

A paired official 4.7.2 run with `--render-thread separate` also completes all
18 live/calibration assertions, then aborts with exit code -6 on shutdown:
`This function (finalize) can only be called from the render thread.` This run
is retained as a failure, not counted among the clean passes. It also produces
the soft-ground synchronization warning. The same source with
`--render-thread safe` exits successfully. This agrees with the existing
desktop engine patch guide; it does not establish the cause of a Windows
in-game freeze. The README now documents the safe source-run configuration;
packaged desktop thread settings are unchanged.

## Scope and further Windows diagnosis

Runtime checks use Linux, NVIDIA RTX 3090 Vulkan and Mesa llvmpipe OpenGL.
They establish the source-level failures and their fixes, not runtime
qualification on the player's Windows laptop, Direct3D 12, or repack.

The project selects Direct3D 12 on Windows and a separate rendering thread on
Windows/Linux. Changing graphics quality does not change that driver. If a
freeze remains after the source fixes, the next evidence is the engine version,
GPU/driver line and final messages from
`%APPDATA%\Godot\app_userdata\Cursed Lands\logs\godot.log` or the game's copied
crash report. The engine's startup header and the game's session trace record
the renderer and GPU.

For an isolated comparison, Godot supports `--render-thread safe`,
`--rendering-driver vulkan`, or
`--rendering-method gl_compatibility --rendering-driver opengl3` before the
`--` separator. These are diagnostic overrides, not a verified remedy for
this laptop. See the [Godot 4.7 command-line reference](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)
and [renderer overview](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html).
The repository's engine patch guide also documents upstream shader-lifetime
and render-thread fixes used by packaged builds; stock editor behavior must
be distinguished from those templates.
