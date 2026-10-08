# Owned renderer adaptations — 8 October 2026

Worktree: `/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008`

Branch: `improve/owned-renderer-wounds-textures`

Starting commit: `3172ede12a5f41b0182c34a70b5eeda787c95e52`

The source audit and priorities are in
[OWNED_RENDERER_IMPROVEMENT_HANDOFF.md](/home/llm2x/Documents/EI/OWNED_RENDERER_IMPROVEMENT_HANDOFF.md).
This checkout is isolated from the ongoing work in
[Optimize game performance](codex://threads/01a117f6-fd90-7190-be5e-9fc0c2bc06aa).
That chat was addressing runes, dialogue cameras, Shelter co-op departure,
party/pet persistence and ability pricing, then creature visibility and low FPS
after a Catacombs transition during this batch. Its checkout is
`/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo`.
Only this worktree and a separate QA directory were changed. No active release
checkout, installed build, Android device or real save profile was modified.

P1 and P2 were selected in the audit's priority order because they can be
implemented in texture-loading/composition code without changing those gameplay
systems. Both are focused first steps; this document does not mark the larger
wound-overlay proposal or the other audit opportunities complete.

## P1: retain outfit pixels for wounds

Implemented the first P1 step. `EIUnitModel._compose` retains the final,
mip-free CPU source image on its newly created texture. `UnitWounds._wounded`
shares that immutable image with its worker instead of calling
`Texture2D.get_image`. The worker still owns and blends a duplicate, so the
original texture/source remains unchanged. Texture ownership controls source
lifetime; clearing wound caches cannot trigger another readback for the outfit.

Custom textures without a retained source keep the existing once-per-cache
readback. The native wound composition, mip generation, material assignment and
late-job rejection remain unchanged. This removes the normal outfit readback;
it does **not** yet implement the larger wound-only shader-overlay proposal or
remove all wound composition/uploads.

Cost: one additional mip-free RGBA8 source per cached outfit texture
(64 KiB for 128 × 128; 16 KiB for 64 × 64), shared across its wound combinations.

### Implementation locations

- [game/src/ei/unit_model.gd:1162](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/ei/unit_model.gd:1162): `EIUnitModel._compose`, source-image producer.
- [game/src/game/unit_wounds.gd:264](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/unit_wounds.gd:264): `_wounded`, metadata consumer and legacy fallback. Metadata key is `UnitWounds.SOURCE_IMAGE`.
- [tools/tests/wound_source.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/wound_source.gd): integration regression and texture readback spy.
- Commit: `e358a10` — `Retain outfit source images for wound composition`.
- Reference renderer: R0 `d529d14e9bf3c960833a9d9633786fc4588ec6d2`, `Source/renderer.cpp` around 5436/5528 and `Source/engine_bridge.cpp` around 6758. Those inspire separation of wound/base lifetimes; this first step does not port their separate draw pass.

### Validation

- Godot 4.7 stable, isolated application-data directories, headless Linux;
  checked in both the editor binary and an exported release executable.
- `tools/tests/wound_source.gd`: **39 checks, zero failures** in each.
- Checks cover byte-identical results including generated mipmaps, zero source
  readbacks, cached fallback readback, immutable source pixels, cache eviction,
  healing while a job is pending, redressing while an older job is pending,
  and three real shipped redress texture sources.
- Same fixture against the starting production code: **six relevant failures**,
  including readback use and missing producer retention.
- The test's texture spy exercises the real wound entry point and worker; a
  headless run is not presented as a GPU frame-time measurement.
- Evidence: `/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa/wound-source-control.log`
  and `wound-source-candidate.log`.
- No FPS gain is claimed. Gameplay/GPU timing and mobile validation remain
  separate from this correctness check.

## P2: preserve authored mip levels and eligible compressed textures

Implemented a separate rendering-image path. The existing `EIMmp.decode` and
default `GameData.load_image/get_texture` behavior still supplies RGBA images
for CPU processing and UI. `Gfx.texture_3d` opts into authored mipmaps for world
objects and foliage **when HD textures are off**. Upscaled textures continue
using regenerated mips for their modified pixels. The default HD option is on,
so this is not an across-the-board reduction for every graphics configuration.

The decoder walks every DXT1/DXT3 level with rounded 4 × 4 block sizes, checks
dimensions, bit count, mip count and available bytes, and preserves every
authored block. All 628 compressed textures in the inspected original
`res/textures.res` have partial chains. Godot's `Image` needs the complete chain
down to 1 × 1, so only the missing tail is generated from the final authored mip.

Compression policy:

- Use compressed data only when `RenderingServer.has_os_feature("s3tc")`.
- Fully supplied opaque DXT1 and DXT3 chains can be uploaded unchanged.
- Partial opaque DXT1 chains retain compression when the last authored level
  is at most 32 × 32. A bounded script encoder fits the newly generated tail
  (at most 16 × 16 and lower levels) to BC1 color palettes. Authored levels are
  never re-encoded. The generated tail is lossy, as expected for BC1.
- DXT1 using its transparent palette index anywhere in its authored chain
  falls back to RGBA. Check all levels, even if the final mip is opaque.
- Partial DXT3, larger missing tails, and unsupported backends use RGBA while
  still retaining authored mip pixels. This bounds loading work and preserves
  alpha without implementing another general-purpose compressor.
- Authored and default/generated texture caches have distinct keys; an earlier
  UI load cannot silently force the rendering path back to its old mip chain.

Two implementation traps were found by validation. Godot 4.7 maps DXT1 to RGB
in both [OpenGL texture storage](https://github.com/godotengine/godot/blob/4.7-stable/drivers/gles3/storage/texture_storage.cpp)
and [RenderingDevice texture storage](https://github.com/godotengine/godot/blob/4.7-stable/servers/rendering/renderer_rd/storage_rd/texture_storage.cpp),
which loses original BC1 foliage transparency without the fallback. Also,
[the CPU S3TC compressor is registered only with TOOLS_ENABLED](https://github.com/godotengine/godot/blob/4.7-stable/modules/etcpak/register_types.cpp).
Do not replace the bounded tail encoder with `Image.compress` merely because
it works in the editor. The final implementation has no such dependency and
was checked with `OS.has_feature("editor") == false`.

### Implementation locations

- [game/src/ei/mmp_texture.gd:45](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/ei/mmp_texture.gd:45): `EIMmp.decode_texture`, header/mip walk, transparency scan and fallback policy.
- [game/src/ei/mmp_texture.gd:131](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/ei/mmp_texture.gd:131): `_pack_bc1_tail`, portable tiny-tail encoding with RGB565 helpers.
- [game/src/ei/game_data.gd:560](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/ei/game_data.gd:560): opt-in `authored_mips` argument; `get_texture` at line 581 keeps cache entries separate.
- [game/src/game/gfx.gd:1037](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/gfx.gd:1037): `texture_3d` is the production opt-in.
- [tools/tests/mmp_texture.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/mmp_texture.gd): synthetic independent mip fixtures, tail quantization, malformed inputs, production cache/capability path and full original compressed corpus.
- [tools/tests/mmp_upload.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/mmp_upload.gd): actual GPU sampling of an opaque building, cutout foliage and an alpha effect, at base, intermediate, last authored and final generated mip levels.
- Reference renderer: R0 `Source/owned_asset_loader.cpp` around 1105/1233 (`parse_texture_asset` around 1297), `Source/renderer.cpp` around 2887 (`Renderer::get_native_owned_texture`), `Source/texture_mips.h` and `Source/world_texture_sampler.h`. The audit contains pinned source links.

### Validation and what the numbers mean

- **5,945 checks, zero failures, 628 assets**, in the editor binary and exported
  Linux release executable. **510 assets retain compression**; 118 use RGBA.
- Sum of resulting image payloads across that fixed compressed-asset corpus:
  **95,533,640 bytes (91.1 MiB)** versus **497,794,320 bytes (474.7 MiB)** for
  RGBA full chains, **80.8% smaller**. This is a payload calculation, not measured
  resident VRAM, total application memory, load-time improvement or FPS. The
  game loads a subset of these assets and other consumers may retain CPU copies.
- Exported Linux build: GPU upload checks passed on **OpenGL Compatibility and
  Vulkan Forward+**, NVIDIA RTX 3090, driver 580.178.04. Captures were inspected;
  foliage cutouts are preserved. Tests compare independent authored RGBA pixels
  for authored mips and CPU-decoded candidate blocks for generated tail uploads.
- Exact equality is required for RGBA fallback rows. Compressed rows allow
  6/255 channel difference for hardware BC interpolation; the observed maximum
  was 5/255. [Independent GPU decoder measurements](https://fgiesen.wordpress.com/2021/10/04/gpu-bcn-decoding/)
  explain the NVIDIA green-channel difference from Godot's CPU decoder. It is
  not evidence that authored compressed bytes changed.
- Existing raw decoder regression: **401 checks, 186 assets, zero failures**.
- Existing lizard trident regression: **3 checks, zero failures** headlessly,
  confirming the P1 producer change preserved the base checkout's recent fix.
- No Android, Web, macOS, Windows or other GPU-vendor runtime test was run.
  Forced unsupported-format fixtures exercise the RGBA fallback independently
  of the tested GPU's capabilities. In-game distance/shimmer review remains useful
  because authored mip artwork can differ from the previous generated chain.

Evidence lives under
`/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa`:

- `export-mmp_texture-headless.log`, `export-wound_source-headless.log`.
- `export-mmp_upload-gl_compatibility.log`, `export-mmp_upload-forward_plus.log`.
- `mmp-native-regression.log`, `lizard-trident-regression.log`.
- `export.log` and the local test executable under `export/`.
- GPU captures under `data/godot/app_userdata/Cursed Lands/mmp-upload-*.png`.

These are QA artifacts, not installed or published packages. Tests run through
the project's existing `--tool=/absolute/path/to/test.gd` entry point with
`--ei-path=/home/llm2x/Documents/EI/inspection/extracted/app`. XDG data/config/cache
directories point inside the QA directory, keeping real saves and settings out
of the run. For GPU checks, use `--render-thread safe --audio-driver Dummy` and
`--rendering-method gl_compatibility` or `forward_plus`; omit `--headless`.

## P3, first stage: retain equivalent foliage materials

Investigation confirmed `EIFigure.build_mesh` already caches figure geometry
by part and complexion. Adding another mesh cache would duplicate existing
behavior. Forward+ also provides automatic instancing for suitable shared
meshes/materials; see [Godot's 3D optimization documentation](https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html).
Compatibility still needs a material uniform for each foliage part's `part_y`.
It previously allocated a fresh `ShaderMaterial` for every placed part, even
when the base material and height were identical.

The first P3 change shares those exact base-resource/height pairs. Keys use the
actual numeric height, without string rounding. Distinct textures, authored
figure materials, sway/stiffness modes and graphics variants retain their own
base resource identities. Each placement retains its original mesh node,
transform, visibility, script identity, navigation geometry and camera-fade
behavior. CameraFade's Compatibility path already creates a separate dither
copy when an individual object fades, then restores its original material.

The variant cache holds weak material references; placed meshes and active
fades own their lifetimes. `set_wind` updates each live variant once and removes
dead entries. `clear_cache` clears variant membership during a data-source
switch. Forward+'s existing instance-uniform path is unchanged.

### Locations and evidence

- [game/src/ei/figure.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/ei/figure.gd): `_foliage_local`, `foliage_variant`, the Compatibility branch in `instantiate`, `set_wind` and existing `clear_cache`.
- [tools/tests/foliage_materials.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/foliage_materials.gd): real tree placements, exact-height separation, material distinctions, individual fade/restore, wind eligibility, weak ownership and cache reset. GPU comparison uses independent per-mesh material copies with a frozen wind clock.
- [tools/benchmarks/scenery_resources.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/benchmarks/scenery_resources.gd): original map resource census. All placement nodes remain alive while counting, so weak sharing is measured correctly. `--scenery-control=/absolute/file.gd` accepts the previous `figure.gd` with its `class_name` declaration removed; the control snapshot used commit `aa5d4fa`.
- Reference renderer: R0 `Source/retained_static_scene.cpp:303` and `Source/retained_static_submission.cpp:394`, immutable placement/resource preparation. This is a Godot resource-retention adaptation, not a port of D3D indirect submission.

With HD upscaling off on Compatibility, the same original static placements
produced these counts:

| Map | Mesh nodes | Unique meshes, unchanged | Material resources before | Material resources after |
|---|---:|---:|---:|---:|
| `bz2g` | 665 | 101 | 644 | 16 |
| `bz4g` | 338 | 221 | 216 | 10 |
| `bz13h` | 494 | 111 | 228 | 10 |

The census's `potential_cell16_merges` is only an upper bound based on equal
mesh/material resources in 16 m cells. It is not measured draw-call reduction
and does not yet account for all lighting, culling, sorting or fade constraints.

Headless Compatibility validation passed **25 checks**. GPU checks passed with
pixel-identical shared/copy images on Compatibility (**28 checks**) and Forward+
(**27 checks**), in both the editor binary and an exported Linux release
(`editor: false`). The fixture's Compatibility draw counts stayed **18 → 18**.
Its Forward+ copied-material control demonstrates automatic instancing, but
the production Forward+ path was already shared before this change; do not
attribute that fixture's draw reduction to a new production optimization.
No frame-time, application-memory-byte or device-performance gain is claimed.

Logs under the QA directory: `scenery-resources-control.log`,
`scenery-resources-candidate.log`, `foliage-materials-headless.log`,
`foliage-materials-gl_compatibility.log` and
`foliage-materials-forward_plus.log`; the release equivalents are
`export-foliage-materials-gl_compatibility.log` and
`export-foliage-materials-forward_plus.log`, from the separate `p3-export/`
build recorded in `p3-export.log`. Captures are
`data/godot/app_userdata/Cursed Lands/foliage-materials-*.png`.

### Explicit batching remains open

P3 is not complete. The next prototype must preserve individual fading and
scripted movement/removal while keeping batches spatially bounded. Specific
integration constraints found in current source:

- `CameraFade._build/_hides/_set_alpha` retains each object's mesh triangles
  and changes only that object's material during a fade. The other chat's
  new `DialogCamera` obstruction check likewise reads individual visible
  `MeshInstance3D` nodes and triangle geometry.
- `TerrainDetails._update_scenery`, `SurfaceWeather.rasterize_cover` and
  navigation inspect the logical mesh nodes. Hiding/removing those nodes to
  suppress their old draw would change those consumers unless they understand
  the replacement representation.
- Godot Compatibility selects a bounded set of lights per geometry. Combining
  several objects may change which local lights they receive; preserve that
  behavior or prove the intended tradeoff before enabling broad MultiMeshes.
- `LocalLighting._light_quality` documents a current engine light-pairing
  constraint: changing mesh/light masks while paired can leave stale light
  references. Do not suppress original draws by changing their layers without
  resolving that lifetime issue.
- Keep levers, effect carriers, animated geometry and per-object overrides out
  of an initial static batch unless they have explicit update handling.

These findings explain the limited first stage. They are implementation work
still to do, not a declaration that broader P3 or P4 is unnecessary.

### Frozen spatial-batch probe

[tools/benchmarks/scenery_batches.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/benchmarks/scenery_batches.gd)
loads the real `bz13h` map, freezes shader time, and compares original meshes,
16 m MultiMesh groups, and restored originals in an 800 × 600 viewport. It
groups matching mesh/material/layer/shadow/part-height values, excludes effect
carriers and deforming meshes, and replaces 248 parts with 87 batches. Original
logical nodes remain visible; only their rendering-server instances are hidden.
This is safe only inside the frozen fixture. No production batching is enabled.

Exported Linux build, RTX 3090, driver 580.178.04, HD upscaling off:

| Renderer | Added point lights | Visible draws before → batched | Changed pixels above 2/255 | Largest channel difference |
|---|---:|---:|---:|---:|
| Compatibility | 0 | 623 → 504 | 0 | 0/255 |
| Compatibility | 4 | 623 → 504 | 3 | 8/255 |
| Compatibility | 12 | 623 → 504 | 1,809 | 33/255 |
| Forward+ | 0 | 898 → 893 | 20 | 28/255 |
| Forward+ | 4 | 898 → 893 | 20 | 28/255 |
| Forward+ | 12 | 898 → 893 | 20 | 25/255 |

The Compatibility four-light difference is at the restoration-control noise
level (three pixels); the twelve-light difference is substantially larger.
This is consistent with Godot's documented per-object MultiMesh light limit
and shows that this grouping does not preserve lighting in the crowded case.
It is not a proof that every changed pixel has the same cause. Forward+'s
small persistent differences remain unexplained, and its draw reduction here
is only five calls. No GPU/CPU time gain is established on either renderer.

Restoring original meshes restored the original draw count in every case.
Pixel restoration was exact except the Compatibility zero-light row's three
pixels. Do not declare the prototype visually equivalent or enable it globally.
Next work needs compatible light membership as well as the lifecycle/fading
constraints above. The other chat was also investigating disappearing creatures;
leave P4 visibility/culling code alone while that investigation is active.

Evidence: `scenery-batches-gl_compatibility.log` and
`scenery-batches-forward_plus.log` under the QA directory, with
`data/godot/app_userdata/Cursed Lands/scenery-batches-*.png` captures. Run the
tool through the same exported `--tool` entry point described above. It exits
successfully when the measurement completes, even when pixels differ; it is a
diagnostic benchmark, not a passing fidelity test.

## P5, first stage: stable local-shadow selection

P4's production visibility changes overlap the other chat's active investigation,
so the next independent change is the local-light selection policy. The original
fire path already favored incumbents by 20%; lava shadow selection had no such
bias. Both could still change abruptly at the eligibility distance, and fire
could exchange shadows every 0.25-second scan when focus movement overcame its
score bias.

The manager now keeps an eligible selected light for two seconds, subject to
the existing shared four-shadow budget and at-most-two lava reservation. After
that minimum, a challenger must beat the incumbent's score divided by 1.25.
This preserves the existing fire score preference and applies it to lava too.
The original distance/focus scoring itself is unchanged; this is not a new
brightness/coverage importance heuristic.

New selections enter within 65 m of the camera. Existing selections can remain
until 69 m, avoiding repeated exchanges at a single cutoff. Frustum eligibility
still applies, and hidden/queued-for-deletion lights do not reserve shadows.
Dropping eligibility bypasses the minimum hold. Tenure uses light instance IDs,
keeps only currently selected entries, and resets for disabled options, loss of
camera, world changes, inactive lava, and pooled lava nodes assigned a new cell.
A light that was externally disabled receives a fresh tenure if reselected.

`Gfx.set_local_shadow` continues to update the Compatibility additive-pass
marker along with the shadow flag. No light mask, particle lifetime, energy
controller, caster transform or render update is delayed. Godot still renders
selected moving lights/casters normally. Selection can still visibly change
after the hold; shadow-strength fades and static/dynamic shadow-map reuse are
not implemented by this step. The hold can intentionally delay a better but
still-visible challenger by up to two seconds; becoming ineligible or shrinking
the available budget takes precedence.

### Source and implementation locations

- Commit: `9bc5ce2` — `Stabilize local shadow selection across camera movement`.
- Reference: R0 [Source/point_shadow_policy.h:11](https://github.com/Ilufus/evil-islands-owned-renderer/blob/d529d14e9bf3c960833a9d9633786fc4588ec6d2/Source/point_shadow_policy.h#L11), `PointShadowPolicy` and `PointShadowScheduler::select`. Its two-second hold, 1.25 score hysteresis and four-unit distance hysteresis inform the adaptation. Upstream uses those policies for eligibility, scheduling and pressure retirement; this is a Godot selection adaptation, not a literal scheduler port. In particular, upstream's four-lamp work budget is **not** a four-resident-shadow limit. Our existing four-shadow cap is retained independently.
- [game/src/game/fx/local_lighting.gd:13](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/local_lighting.gd:13): policy constants and `_shadow_since` state.
- [game/src/game/fx/local_lighting.gd:365](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/local_lighting.gd:365): `_shadow_candidate`, `_select_shadows` and `_assign_shadows`.
- Same file: `apply_options`, `_clear_lava`, `_process`, `_sync_lava` and `_disable_shadows` invalidate selection history at the corresponding lifetime boundaries.
- [tools/tests/local_shadow_selection.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/local_shadow_selection.gd): actual manager/camera/light integration, plus an optional real-GPU fixture using the production figure shader.

### Evidence and limits

The deterministic eight-second trace alternates focus across five clustered
fire lights every 0.25 seconds while keeping four shadows available. The old
manager changed its selected set **31 times**; the new manager changed it
**3 times**. This is an explicit policy trace, not measured game FPS or a claim
about all camera movements.

The exported Linux executable passed **377 headless checks**, and **418 checks
on each of OpenGL Compatibility and Vulkan Forward+**, RTX 3090. Tests cover
hold expiry, eventual replacement, ordering, distance thresholds, hidden/freed/
queued lights, moving lights, lava competition, shrinking the fire budget, pool
reuse, option restoration, camera reset and world cleanup. The current fixture
against the previous manager from commit `3855cc4` fails ten relevant checks;
the control script has only its `class_name` line removed for isolated loading.

The rendered fixture holds the camera and illumination constant while focus
requests a different shadow selection. During the minimum hold, captured pixels
are identical on both backends. When the hold expires, 61,050 Compatibility
pixels / 47,267 Forward+ pixels change by more than 2/255, showing a real visible
shadow transition. Moving the invisible shadow caster while a light is held
changes 17,486 / 23,272 pixels, and moving the selected light also updates the
image. Thus the hold does not freeze the caster's rendered shadow. These are
fixture pixel counts, not image-quality scores or performance gains.

An older scratchpad `local_lighting_test.gd` was also run. It reports the same
two spell-flash energy/restoration expectation failures on both the frozen
pre-P5 build and the candidate; all other checks in that fixture pass. This
legacy fixture is not reported as green, and unrelated spell timing was not
changed to satisfy its older expectations. Evidence: `local-lighting-control.log`
and `local-lighting-regression.log` under the QA directory.

Current validation logs: `export-local-shadow-selection-headless.log`,
`export-local-shadow-selection-control.log`,
`export-local-shadow-selection-gl_compatibility.log` and
`export-local-shadow-selection-forward_plus.log`. The frozen release is under
`p5-export/`, built with `p5-export.log`; images are
`data/godot/app_userdata/Cursed Lands/local-shadows-*.png`. Editor GPU runs also
passed. No mobile, other-vendor GPU, full gameplay soak or frame-time benchmark
was performed for this policy change.

## P6 investigation: directional-shadow snapping

At the start of this batch, the remake separated direct lighting from a held
shadow direction on all Compatibility renderers and on mobile/web
(`Game._aim_sun`, `Game.sun_basis`, `Portability.held_sun`). Desktop Forward+
kept continuous aiming. The existing
held policy re-aims on zone/view changes, camera cuts, and a ten-degree lag cap.
`shadow_diag.gd` already provides aim, roll, atlas, split and bias comparisons.

The exact Godot source used by these builds already fits camera-slice spheres,
reserves border texels and snaps their projected bounds to a texel grid.
Directional shadow setup runs for the visible shadowed lights during rendering;
snapping only the sun direction does not establish retained depth-map reuse.
See [_light_instance_setup_directional_shadow](https://github.com/godotengine/godot/blob/5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/servers/rendering/renderer_scene_cull.cpp#L2150),
especially lines 2273–2319, and its call around line 3387. Do not add a second
camera-position snapping approximation in GDScript without an engine-level
reason and coverage tests.

Reference R0 `retained_static_submission.cpp:187` snaps normalized direction
components to 1/512 and renormalizes, retaining exact direct sunlight. Its
`finish_shadow_receiver_xy` around line 883 additionally quantizes coverage
radius and reserves filter support. The following experiment evaluates only
the direction policy, not that entire fitting/reuse pipeline.

[tools/benchmarks/directional_shadows.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/benchmarks/directional_shadows.gd)
compares continuous, 1/512-component snapping and the existing held aiming code
on the real `bz13h` map. It freezes wind/time and direct illumination, uses a
fixed camera, 480 × 360 pixels, a 2048 atlas and 31 azimuth samples spaced by
0.02 degrees. Samples describe a controlled angular trace, not actual frame
timing. A no-shadow control changes zero pixels on both backends, isolating
the measured differences to shadows in this fixture.

| Renderer | Policy | Direction changes across 30 steps | Median changed pixels per step | Peak changed pixels per step |
|---|---|---:|---:|---:|
| Compatibility | Continuous | 30 | 869 | 939 |
| Compatibility | Snap 1/512 | 4 | 0 | 1,463 |
| Compatibility | Held | 0 | 0 | 0 |
| Forward+ | Continuous | 30 | 471 | 510 |
| Forward+ | Snap 1/512 | 4 | 0 | 963 |
| Forward+ | Held | 0 | 0 | 0 |

Changed pixels require a channel difference above 2/255. Snapping exchanges
frequent small changes for fewer larger ones; a lower median alone is not
proof of smoother-looking animation. The maximum snapped direction error was
0.076 degrees. Held direction error reached 0.405 degrees over this short
trace, below its existing ten-degree re-aim threshold. The test does not assess
that larger re-aim event, moving/zooming cameras, low sun, mobile GPUs or cascade
coverage. Neither a quality improvement nor a speedup is established for a new
projection algorithm. These results do not justify replacing the constrained-
device fallback with fine snapping, or enabling that fallback on desktop.

The exported Linux build completed the probe on RTX 3090, OpenGL Compatibility
and Vulkan Forward+. Logs: `directional-shadows-gl_compatibility.log` and
`directional-shadows-forward_plus.log` in the QA directory; first/last captures
are `data/godot/app_userdata/Cursed Lands/directional-shadows-*.png`. The inspected
pinned engine file is saved there as `godot-5b4e0cb-renderer_scene_cull.cpp`.
P6 remains an investigation, not a completed shadow-caching implementation.

### User clarification: constrain the fallback, not desktop sunlight

The user clarified that holding was introduced for Android/web shimmer and
cost, is unnecessary on desktop, and is optional even on Android if a better
and cheaper implementation is demonstrated. Treat it as a fallback, not the
desired universal rendering behavior. The frozen-direction probe above cannot
establish mobile performance or choose a mobile replacement by itself.

`Portability.held_sun` previously returned true for desktop Compatibility too.
It now defaults to holding only on constrained platforms (mobile/Android/web),
or with the existing explicit `--held-sun` diagnostic override. Desktop sunlight
follows the clock on Compatibility, Forward+ and Mobile renderers. Game and
menu paths both use this policy. Compatibility retains its projection roll and
2.0 normal-bias correction independently of whether aiming is held; Forward+'s
normal 1.2 bias is unchanged. The existing `--shadow-diag=continuous` can bypass
holding for device comparisons. No Android/web default was removed without
device evidence.

Changed production files: `game/src/platform/portability.gd`,
`game/src/game/game.gd` and `game/src/ui/menu_scene.gd`.
[tools/tests/sun_aiming.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/sun_aiming.gd)
exercises actual game setup/aiming and menu clock changes, small clock motion,
lag-cap catch-up, zone re-aims, preserved bias/roll, and the continuous diagnostic
override. Ten checks pass per run in the exported Linux build on both renderer
settings, normally and with `--held-sun` (four runs). The old exported build
fails four relevant desktop-Compatibility expectations. These are headless
policy checks, not GPU/mobile performance tests. The separate GPU direction
trace above already evaluated continuous Compatibility with the retained roll
and bias, but does not establish subjective quality on every device.

Evidence: `sun-control.log`, `sun-gl.log`, `sun-gl-held.log`, `sun-forward.log`,
`export-sun-gl_compatibility.log`, `export-sun-gl_compatibility-held.log`,
`export-sun-forward_plus.log`, `export-sun-forward_plus-held.log`, plus
`p6-export.log` and the isolated `p6-export/` release. No installed build or
other chat's working files were changed.

## Integration

The implementation is in this isolated branch. Do not overwrite another agent's
working checkout or installed packages to test it. Integrate the focused commits
once the active source owner can accept them, preserving their newer changes.

P1 changes only `unit_model.gd` and `unit_wounds.gd` plus its test/documentation.
P2 changes only `mmp_texture.gd`, the texture-loading methods in `game_data.gd`,
and `Gfx.texture_3d` plus its tests/documentation. No network, inventory,
campaign-state, pricing or dialogue-camera behavior was edited.
The first P3 stage changes only `figure.gd`, its resource census, regression
fixture and this documentation. No object ownership or camera code was changed.
The P3 probe is a standalone benchmark only (commit `3855cc4`). P5 changes only
`local_lighting.gd` plus its regression fixture and documentation.
The P6 comparison is a standalone benchmark. The subsequent user-directed
default correction changes only sun policy/setup and menu sun aiming, plus its
test; it does not modify character visibility or zone-transition code.

Read-only `git apply --check` of the combined P1, P2, P3 and P5 patch through
`9bc5ce2` passed against the active checkout at
`083ef5a9b5cc534cb73a5b0d72f9ea571d6426a1`. Its working tree was clean and its
HEAD/status were unchanged across the check. No patch was applied. Evidence:
`integration-check-p5.json` in the QA directory. Recheck before integrating
because that checkout is still changing.

## Next work in the established order

1. **P3 static scenery batching:** material retention, a three-map resource
   census and the frozen rendered-map probe are now recorded above. The probe
   found a crowded-light mismatch; resolve compatible light membership and the
   listed consumers before a production batch. `map_scene.gd` and `figure.gd`
   are the main entry points. Preserve the recent dialogue-obstruction work
   before changing visual ownership.
2. **P4 occlusion:** after identifying hidden-geometry cost, evaluate Godot's
   existing facilities before a custom Hi-Z path. Keep world/gameplay visibility
   separate and verify camera movement, thin openings and shadows.
3. **P5 local shadows, then P6 directional stability:** the first stable-selection
   step and real-GPU transition checks are implemented above. Shadow-strength
   transitions, better importance scoring and cached map updates remain separate
   work. For P6, identify actual shimmer/redraw cost and renderer capabilities
   before changing cascade settings or planning engine-level projection reuse.
4. **C1 character batching/skinning:** keep as an isolated prototype until the
   main character/gameplay changes settle. The active remake still animates rigid
   figure parts. Converting to a skinned mesh was an author suggestion, not an
   implemented upstream feature or a demonstrated speedup.
5. **Visual track:** V1 ground-contact blending, V4 water interaction, V2 biome
   ground cover, then the remaining audit features. These remain proposals;
   none was silently enabled in this performance batch.
