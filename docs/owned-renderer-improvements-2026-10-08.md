# Owned renderer adaptations — 8 October 2026

Worktree: `/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008`

Branch: `improve/owned-renderer-wounds-textures`

Starting commit: `3172ede12a5f41b0182c34a70b5eeda787c95e52`

The source audit and priorities are in
[OWNED_RENDERER_IMPROVEMENT_HANDOFF.md](/home/llm2x/Documents/EI/OWNED_RENDERER_IMPROVEMENT_HANDOFF.md).
This checkout is isolated from the ongoing work in
[Optimize game performance](codex://threads/01a117f6-fd90-7190-be5e-9fc0c2bc06aa).
That chat was addressing runes, dialogue cameras, Shelter co-op departure,
party/pet persistence and ability pricing during this batch. Its checkout is
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

Read-only `git apply --check` of P1, P2 and the first P3 stage passed against the active
checkout's working files while its committed HEAD was
`ab62e0296476daa481bd1abd20833fcb8084cc2d`, including its unrelated uncommitted
gameplay work. No patch was applied. Recheck before integrating because that
checkout is still changing.

## Next work in the established order

1. **P3 static scenery batching:** material retention and a three-map resource
   census are now implemented above. Next, measure a dense rendered map and
   prototype compatible static batches in bounded cells, addressing the listed
   consumers and light-selection constraints. `map_scene.gd` and `figure.gd`
   are the main entry points. Preserve the recent dialogue-obstruction work
   before changing visual ownership.
2. **P4 occlusion:** after identifying hidden-geometry cost, evaluate Godot's
   existing facilities before a custom Hi-Z path. Keep world/gameplay visibility
   separate and verify camera movement, thin openings and shadows.
3. **P5 local shadow selection, then P6 directional stability:** policy changes
   can be separate from gameplay; require actual shadow-transition evidence and
   renderer capability checks before promising cached shadow-map updates.
4. **C1 character batching/skinning:** keep as an isolated prototype until the
   main character/gameplay changes settle. The active remake still animates rigid
   figure parts. Converting to a skinned mesh was an author suggestion, not an
   implemented upstream feature or a demonstrated speedup.
5. **Visual track:** V1 ground-contact blending, V4 water interaction, V2 biome
   ground cover, then the remaining audit features. These remain proposals;
   none was silently enabled in this performance batch.
