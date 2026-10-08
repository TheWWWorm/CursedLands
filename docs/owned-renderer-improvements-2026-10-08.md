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

### Batching constraints established at the material-reuse stage

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

### Light membership: preserve complete sets and engine history

The standalone prototype at this checkpoint resolved the large Compatibility
mismatch in the frozen probe. Live object/fade and light lifecycle handling
was still pending; the subsequent opt-in runtime implementation is recorded below. The reference renderer's immutable
compatible-submission groups remain the model; the light-selection rules below
are specific to our pinned Godot build.

Implementation and evidence:

- [scenery_batch_lights.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/benchmarks/scenery_batch_lights.gd)
  partitions an already mesh/material-compatible cell by complete light sets.
  It checks each member's world AABB and the proposed merged AABB. A light in
  the gap between two objects must not silently enter their combined set.
  Per-type budgets and geometry/light masks are respected. Any truncated set
  keeps its original mesh. A separate ranked mode is a **negative control**.
- [scenery_batches.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/benchmarks/scenery_batches.gd)
  now accepts `--scenery-light-partition`, `--scenery-ranked-lights`,
  `--scenery-map=<name>`, `--scenery-shadows` and `--scenery-no-wind`.
  It adds an energy-only change after the twelve-light capture, records batch
  construction time and JSON results, and includes expanded bounds when
  building a MultiMesh AABB. Default invocation retains the naive control.
- [scenery_batch_lights.gd (tests)](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/scenery_batch_lights.gd)
  passes **15 headless boundary checks**, including a new light inside the merged
  bounds, four/eight-light budgets, per-type limits, masks, ties, total-cap
  ambiguity and caller-record preservation.
- [scenery-light-groups-2026-10-08.json](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/docs/validation/scenery-light-groups-2026-10-08.json)
  retains ten exported GPU cases, exact commands, 120 capture hashes, the
  native-engine evidence, source/pack hashes and the integration check. Each
  GPU case has four off/batched/restored triplets. These are measurements;
  successful process exit alone is not a fidelity pass.

Godot's
[RendererSceneCull::_scene_cull, line 3019](/home/llm2x/Documents/EI/local/scratchpad/coop-performance-20261005/engine-profile/godot-5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/servers/rendering/renderer_scene_cull.cpp:3019)
updates a geometry's bounded light list only when its pairing is dirty. The score
at line 3054 is transformed-AABB-centre distance divided by
`max(light_range * light_energy, 0.01)`. Combining geometry changes that centre.
More subtly,
[LightStorage::light_set_param, line 144](/home/llm2x/Documents/EI/local/scratchpad/coop-performance-20261005/engine-profile/godot-5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/drivers/gles3/storage/light_storage.cpp:144)
does not notify a pairing change for energy alone. Recomputing the top eight
from current values therefore need not match an existing mesh's retained list.
[instance_set_visible, line 1046](/home/llm2x/Documents/EI/local/scratchpad/coop-performance-20261005/engine-profile/godot-5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/servers/rendering/renderer_scene_cull.cpp:1046)
unpairs hidden geometry, so restoring it can itself change the selected lights.

The negative control makes this observable on `bz13h`: ranking current lights
removes the initial twelve-light mismatch, but boosting the last light's energy
changes **295 pixels**; restoring originals changes **294 pixels**. The guarded
planner preserves full sets within the budget and leaves overloaded originals
untouched. It reduces that energy-change difference to **three pixels**.

Final Compatibility twelve-light results, pixels counted above 2/255:

| Map / setup | Per-type budget | Original → batched draws | Initial changed pixels | After energy change |
|---|---:|---:|---:|---:|
| `bz2g` | 8 | 453 → 414 | 0 | 0 |
| `bz4g` | 8 | 340 → 337 | 0 | 0 |
| `bz13h` | 8 | 623 → 530 | 0 | 3 |
| `bz13h`, four-light override | 4 | 623 → 540 | 0 | 0 |
| `bz13h`, sun + four local shadows | 8 | 1,865 → 1,607 | 0 | 9 |

The four-light result uses a separate exported runtime with `override.cfg`,
loaded before renderer initialization. Its executable, pack and native sidecar
match the desktop baseline; the report confirms a limit of four. This tests the
budget used by Android/web, **not physical mobile/browser performance**.
With no added lights, the three Compatibility maps reduce 453→382, 340→336 and
623→504 draws respectively. The sparse `bz4g` fixture has little batching benefit.

Residual `bz13h` differences are not hidden: up to three pixels without shadows
and nine with shadows, with original/restored controls also varying in some rows.
Forward+ still changes 15–20 pixels and can increase draws from 898 to 907 in the
crowded guarded case. Its existing automatic instancing already does most of
this work; do not enable this manual approach there based on these results.
Construction of all batches took roughly 1.5–6.3 ms in these desktop samples.
That includes snapshot/planning/node setup, is not frame submission time, and
must not become an unconditional per-frame rebuild.

The wider-map fixture needed a correction: grass continued arriving from workers
and water changed between captures. Initial results with tens of thousands of
changed pixels were invalid as batching evidence. Final runs wait for grass
queues/jobs (22–38 frames here), stop map processing, then freeze shader `TIME`
for all now-existing geometry. The invalid exploratory reports are retained only
under `p3-light-plan/unsettled-*.json` in QA, not used in the table above.

Next implementation requirements remain concrete:

1. Build a Compatibility manager with spatially bounded groups and incremental
   changes. Track creation/removal, visibility, transforms, bounds, range and
   masks of relevant lights before the affected draw. Energy flutter alone does
   not require repartitioning a complete set. Keep overloaded originals intact.
2. Preserve each logical mesh for picking, dialogue obstruction, navigation,
   weather and grass exclusion. Handle individual fade/material swaps explicitly;
   temporarily returning an affected object to its original renderer is viable.
3. Handle scripted movement/removal and world teardown without stale slots,
   hidden originals or leaked shared resources. Cover ground-contact option
   changes, wind and per-part height, shadow masks and all existing consumers.
4. Measure ongoing CPU submission and GPU/culling cost with moving cameras,
   light churn and individual fades, then validate target devices. The current
   result solves a selection constraint; it is not completed P3 or an FPS claim.

## P3: opt-in live Compatibility scenery batches

The frozen planner now has a world-owned runtime manager. Enable it with
`--scenery-batches` after the executable's `--` separator. It remains off by
normal default, including Android/web, pending broader gameplay and device
acceptance. Forward+, Mobile and headless automatic initialization bypass it.
This is a live implementation checkpoint, not a claim that all P3 work is done.
The reference basis remains R0 `Source/retained_static_scene.cpp:303`,
`Source/retained_static_submission.cpp:394` and `Source/renderer.cpp:6851`:
retain compatible immutable geometry while preserving logical identity.

### Runtime ownership and integration contract

- [scenery_batches.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/scenery_batches.gd)
  owns 16 m cell groups, weak object/light references, dirty groups and draw
  instances. It registers placed `OBJECT` figures only; units, levers and `ef`
  effect carriers are excluded. Skins, blend shapes, fading meshes, overlays,
  custom bounds, distance/parent visibility and unsupported materials stay on
  their original path. A visible reflection/GI volume disables grouping because
  its per-instance selection is not modeled by this first implementation.
- [scenery_batch_watch.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/scenery_batch_watch.gd)
  is a non-rendering child of each registered mesh. It observes inherited
  transforms, visibility, tree exits and mesh-resource changes. The manager
  never removes/reparents an authored mesh or changes its logical visibility,
  layer mask or gameplay record. Only the original RenderingServer instance's
  draw visibility is suppressed while a compatible MultiMesh represents it.
  Picking, weather/navigation queries and camera obstruction still see the
  individual original nodes and geometry.
- [scenery_light_groups.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/scenery_light_groups.gd)
  is the promoted complete-light-set policy. The former benchmark helper now
  inherits this production helper, so boundary tests and diagnostics exercise
  the same policy. Ranked overflow remains only a diagnostic negative control.
  Runtime code never asks for it.
- [map_scene.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/ei/map_scene.gd)
  creates the manager on ready when requested and registers later `place_object`
  results. This includes quest `AddMob` scenery through the existing world API.
  No character, visibility/LOS, script or zone-transfer code was changed.
- [camera_fade.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/ui/camera_fade.gd)
  and [ground_contact.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/ground_contact.gd)
  notify the manager **before** replacing a material. The first camera fade
  restores the affected original immediately; continuing the fade does not
  rebuild groups. Completion can rejoin a compatible group. Contact options
  and replacements while faded preserve the existing material/fade contract.

Future writers that replace a registered mesh's material, geometry or render
state must call `SceneryBatches.changed(mesh)` **before** that replacement.
A new mesh resource is then observed on the next flush. Shared material-uniform
updates need no special notification because batches share that resource.
The current placed-scenery material writers are hooked; this is not a generic
interceptor for arbitrary third-party property changes.

Once a registered object moves, it stays on its original renderer until the
manager is torn down/reinitialized, even when batching is toggled off/on. The live control test
exposed why: copying a freshly moved global transform into a new MultiMesh can
jump ahead of Godot's retained/interpolated transform. This implementation is
for static scenery and preserves the moving object's original render history.
Parent movement also restores the affected original instances. A new manager
can register the world's now-current placements after teardown/re-entry.

Light snapshots are confined to the same `World3D`. Creation, deletion,
visibility, bounds/range, position and cull-mask changes dirty intersecting
logical groups, including the entire union where a light can enter a gap.
Energy-only flicker deliberately does not rebuild or re-rank. A moving light
whose complete-set partitions remain the same retains existing batch objects;
the engine updates their light pairing. The manager polls tracked lights before
drawing; it does not rescan the scene tree or poll all mesh transforms every
frame. Exit restores original draws, disconnects signals, clears weak tables
and frees watchers. Removed/re-added managers reinitialize their watches.

### Rendered tests, observed savings and remaining limits

[tools/tests/scenery_batches.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/scenery_batches.gd)
uses two separately rendered worlds with identical inputs; one never batches.
The exported release passes **110 checks on each of Compatibility budget 8,
Compatibility budget 4 and Forward+**, with zero pixels over 2/255 in all live
comparison frames. Coverage includes camera movement, logical visibility,
object/parent movement, hide/show, fade start/continuation/restore, a material
replacement during a fade, shared mesh mutation, render-state replacement,
light creation/movement/range/visibility/removal/energy, over-budget fallback,
probe fallback, object creation/deletion/reparenting, off/on, manager re-entry
and teardown. Forward+ keeps original draws throughout. The eight-mesh static
fixture reduces eight draws to two only on Compatibility.

The promoted planner's **15 boundary checks** pass against the exported runtime;
the existing contact material/field regression also passes **35 checks**. The
small fixture does not establish behavior for every gameplay script or asset.
The Forward+ fixture reports seven leaked Texture RIDs at shutdown when it
creates and frees a temporary ReflectionProbe. An otherwise identical fixture
without that probe passes 105 checks with no leak warning; the production
manager creates no textures and automatically bypasses Forward+. The probe
warning is retained in the evidence, not counted as a clean shutdown result.

The real-map benchmark's `--scenery-batches` route exercises `EIMapScene._ready`
and the production manager, rather than its older diagnostic constructor.
Original / batched / restored comparisons use a settled, frozen camera and
scene, 800 × 600, original textures, Godot 4.7 `5b4e0cb0f`, Linux release,
Compatibility, NVIDIA RTX 3090 / driver 580.178.04:

| Scene | No added lights: original → batched draws | Twelve added lights | Changed pixels above 2/255, initial / energy change |
|---|---:|---:|---:|
| `bz2g`, budget 8 | 453 → 382 | 453 → 414 | 0 / 0 |
| `bz4g`, budget 8 | 340 → 336 | 340 → 337 | 0 / 0 |
| `bz13h`, budget 8 | 623 → 504 | 623 → 530 | 0 / 3 |
| `bz13h`, budget 4 | 623 → 504 | 623 → 540 | 0 / 0 |
| `bz13h`, sun/local shadows + contact blend | 1,558 → 1,247 | 1,865 → 1,607 | 9 / 9 |

Normal `bz13h` restoration controls also differ by up to three pixels. The
combined shadow/contact row has nine persistent differing pixels (maximum
34/255 channel delta); restoration is exact in that run. Isolating the effects
gives three persistent pixels with contact alone and up to nine with shadows
alone; shadow-only restoration also differs by nine in one phase. The counts
and maximum deltas match the prior restoration variation, but their exact
cause is unresolved. Keep this residual visible rather than calling every
real-map capture pixel-identical. Forward+ automatic bypass retains **898 → 898** draws and
exact pixels for all four light/energy phases. One Forward+ attempt was excluded
because grass streaming did not settle before the fixture limit; the retry
settled and completed. Successful benchmark exit means measurement completed,
not that image differences passed an acceptance threshold.

In the isolated recorded `bz13h` cost sample, 32 idle updates measured a median
**34 microseconds**, range **3–62 microseconds**. Moving one of four added lights
through a 3 m sweep measured a median **746.5 microseconds**, maximum **928
microseconds**, with zero to two affected groups rebuilt per frame. These are
manager CPU durations, not GPU time or an FPS improvement. No other game/editor
render process was present at the sample's start or end. Complete rebuilds in
the map comparison samples took roughly **3.4–9.1 ms**. Initial loading,
option-wide invalidation and local light churn therefore still have costs;
retaining original nodes also means this is not a scene-memory reduction.

Physical Android/browser performance, thermal behavior, long gameplay routes,
additional GPUs, the shadow/contact residual and user-facing rollout remain
open. The four-light override is a desktop engine-budget test only. Keep the
flag opt-in until saved submission work outweighs CPU management cost on the
intended target. The existing V1 effect stays off by default independently.

Evidence, commands, source/build hashes, pixel deltas, warnings and the read-only
integration check are retained in
[scenery-runtime-2026-10-08.json](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/docs/validation/scenery-runtime-2026-10-08.json).
Full per-frame reports/captures and rejected attempts are under
`/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa/p3-runtime`.
Reproduce the map/cost path through the existing exported `--tool` runner with
`tools/benchmarks/scenery_batches.gd --scenery-batches --scenery-churn`;
`--scenery-contact` and `--scenery-shadows` add those independent conditions.

## P3 acceptance follow-up: native overlap control and actual cost

The previous nine-pixel shadow/contact residual is now reproduced **without
constructing or drawing any MultiMesh**. The benchmark's
`--scenery-reinsert-control` removes and immediately restores only the original
scenery instances' RenderingServer visibility. All authored meshes, materials,
transforms and logical nodes remain unchanged. In the same `bz13h` camera,
reinserting 494 originals leaves the draw count at **1,558 → 1,558**, yet changes
the exact same nine pixels. Its resulting PNG is byte-identical to the prior
batched shadow/contact capture (SHA-256
`d9a7145bc8a7e901bc26d71daec2124a6d94673768182864a2a60ed5d102f31f`).

`--scenery-trace-pixels` attributes up to 16 changed pixel centres in the first
comparison to original CPU triangles. All nine affected pixels hit overlapping
`stwa13` / `hadoganwall01` wall pieces, notably nids 43003 and 43005–43008.
The nearest two hits at pixel (603,180) are approximately 91.36478 and 91.36516 m
from the camera: about 0.38 mm apart along the ray. This supports a depth/order
sensitivity in existing overlapping geometry, rather than a contact-texture or
complete-light-set mismatch. The pinned GLES3 renderer sorts opaque surfaces
by material/shader/mesh/depth keys
([key assignment, line 331](/home/llm2x/Documents/EI/local/scratchpad/coop-performance-20261005/engine-profile/godot-5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/drivers/gles3/rasterizer_scene_gles3.cpp:331),
[key comparator, line 695](/home/llm2x/Documents/EI/local/scratchpad/coop-performance-20261005/engine-profile/godot-5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/drivers/gles3/rasterizer_scene_gles3.h:695));
there is no unique placement key for otherwise equal surfaces.

Keep this conclusion scoped to the reproduced pixels. Other cameras or future
changes still need their own original/reinserted controls. Near-clip diagnostics
(`--scenery-near=0.5` and `=2.0`) move or reduce some mismatches but expose others;
no camera or authored-geometry change was made to production. The triangle
tracer uses the fixed camera's global transform and local ray direction, avoiding
an unpumped interpolated camera cache in manually forced render fixtures. It is
an attribution aid for rigid geometry, not an oracle for GPU wind/deformation.

### Cache immutable bounds; preserve membership invalidation

[SceneryBatches](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/scenery_batches.gd)
now lazily caches each compatible group's union. Light movement reuses it;
member insertion, removal, movement, mesh/material/state replacement and teardown
invalidate or clear it. Singleton groups skip both light-change intersection
work and complete-light planning, because they cannot make a batch. The light
selection policy, originals, grouping keys and rendered output are unchanged.
This is the retained-static principle from R0 `retained_static_scene.cpp:303`
applied to the runtime manager's own CPU work.

The expanded
[live regression](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/scenery_batches.gd:206)
passes **119 checks each** on Compatibility budget 8, Compatibility budget 4 and
Forward+ bypass. The new boundary case populates the cached bounds, widens the
shared meshes, then introduces over-budget lights beyond their old bounds.
The enlarged affected pieces return to originals while the unaffected cell
remains batched. All live comparison frames match the independent unbatched
world. The earlier Forward+ temporary-probe shutdown warning remains recorded.

### Fewer draws did not improve this desktop render sample

The benchmark now measures render cost with `--scenery-timing`. Each condition
uses six alternating windows (three per state), with 24 warmup and 96 measured
frames per window. During the unbatched timing control the manager's draw
callback is disconnected, so the baseline does not pay its light polling cost.
`force_draw_usec` includes the manager callback and the synchronous render
submission; viewport CPU/GPU measurements are also retained. No image readback
or pixel comparison occurs inside a measured window. This is a frozen scene,
not full gameplay frame time or a portable FPS result.

`--scenery-game-camera` uses the current modern camera's 55° field of view and
`Gfx.far_clip()` (260 m in these runs), retaining the 0.05 m near plane. The
same scene then draws **489 → 407** with no added lights and **489 → 417** with
four. Even so, its median window render-submission time is higher with batches:

| Cached candidate, `bz13h`, RTX 3090 / Compatibility | Original instances | Batches | Manager component when batched |
|---|---:|---:|---:|
| No added lights | 1.601 ms | 1.758 ms | 0.005 ms |
| Four stationary lights | 1.878 ms | 1.963 ms | 0.027 ms |
| Four lights, one moving through a 3 m sweep | 1.693 ms | 2.295 ms | 0.464 ms |

The prior manager's corresponding moving-light component was **0.774 ms**;
caching reduces that sampled component by about **40%**. Its total moving-light
submission time was 2.649 ms versus the same 1.693 ms original-instance control.
All six old/new map PNGs are byte-identical. The other baseline window medians
vary between runs, so do not interpret every old/new timing difference as a
code effect. Native viewport CPU time also rises in several batched windows,
and GPU timing does not establish a compensating benefit on this GPU.
No other game/editor render process was present at these runs' start or end.

Here “old/new” compares the previous manager with the cached candidate, not
original instances with batches. With this modern lens the latter still differ
by 16 pixels without added lights and two with four lights (maximum 8/255);
14 pixels persist after restoring originals. Those pixels have not received
their own reinsertion/triangle attribution, so the nine-pixel conclusion above
must not be extended to them. The bounds cache preserves the previous results.

**Rollout remains off by default.** The manager is cheaper, but this desktop
measurement contradicts using draw count alone as evidence of a speedup.
Android hardware and browsers may have different submission costs; they require an
actual benefit before a default is justified. Avoid spending further desktop
work on rollout without identifying a workload where batching wins. P4 should
start with measured hidden-geometry cost and preserve the other chat's logical
visibility/guard work; its recent changes are in story/co-op scripts.

Commands, source/export hashes, timing windows, lifecycle results, the exact
reinsertion control and the integration check are in
[scenery-batch-costs-2026-10-08.json](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/docs/validation/scenery-batch-costs-2026-10-08.json).
The cached export and full reports are under the isolated QA `p3-seams`
directory; `p3-runtime/export` remains the frozen `3240251` reference.

## P4 diagnostic: native occlusion has a scene-dependent cost

The owned renderer's R0
[terrain Hi-Z construction](/home/llm2x/Documents/evil-islands-owned-renderer/Source/renderer_occlusion.cpp:37)
and [same-frame/camera guard](/home/llm2x/Documents/evil-islands-owned-renderer/Source/renderer_occlusion.cpp:110)
remain useful references. Godot already has a different implementation that
should be evaluated first: CPU ray casting through occluder geometry, a small
hierarchical depth buffer, and conservative instance-bound tests. It is shared
by Compatibility and Forward+, not a missing GLES-only GPU feature.

Relevant pinned local engine sources:

- [ray buffer update](/home/llm2x/Documents/EI/local/scratchpad/coop-performance-20261005/engine-profile/godot-5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/modules/raycast/raycast_occlusion_cull.cpp:597);
- [viewport ray budget and dimensions](/home/llm2x/Documents/EI/local/scratchpad/coop-performance-20261005/engine-profile/godot-5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/servers/rendering/renderer_viewport.cpp:316);
- [camera visibility test](/home/llm2x/Documents/EI/local/scratchpad/coop-performance-20261005/engine-profile/godot-5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/servers/rendering/renderer_scene_cull.cpp:2927) and the separate [directional-caster collection](/home/llm2x/Documents/EI/local/scratchpad/coop-performance-20261005/engine-profile/godot-5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/servers/rendering/renderer_scene_cull.cpp:3241);
- [occlusion hysteresis](/home/llm2x/Documents/EI/local/scratchpad/coop-performance-20261005/engine-profile/godot-5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/servers/rendering/renderer_scene_occlusion_cull.h:175);
- [web template default](/home/llm2x/Documents/EI/local/scratchpad/coop-performance-20261005/engine-profile/godot-5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/platform/web/detect.py:85): `module_raycast_enabled` is false. Desktop availability is not evidence that the browser build has it.

### What the new probe measures

[terrain_occlusion.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/benchmarks/terrain_occlusion.gd)
loads a real map without gameplay units, retains its logical nodes, and toggles
only a private SubViewport's native occlusion. No production hook, option or
occluder manager was added. Both controls disable soft-ground deformation,
ground-contact blending, HD upscaling and volumetric effects. Grass and sun
shadows are separate flags. The camera uses the modern 55° lens, 260 m far plane
in these runs, and six fixed overview/low/opposite poses around dense scenery
and the map centre.

The initial terrain proxy copies **actual tile vertices and indices** from
[EITerrainSector](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/ei/terrain_sector.gd:22),
including authored horizontal offsets. Each sampled map contributes 16 sectors
and 32,768 triangles. This establishes a reference before coarse simplification;
it is not an optimized low-polygon occluder mesh. Reconstructing the height grid
or filling object bounds with solid boxes would not preserve holes/silhouettes.

`--occlusion-opaque-objects` additionally admits rigid visible OBJECT meshes
using the known non-deforming figure shader, with no skin, blend shape, extra
pass or transparency. Every alpha byte in every mip must be 255; actual mesh
triangles retain geometric openings. The frozen fortress admits 274 meshes /
13,358 triangles after checking eight textures. This deliberately excludes
alpha-cutout atlases and all foliage. It is **not** a production lifetime rule:
camera fading, scripted movement and material/visibility changes would require
immediate conservative invalidation. Native occluder BVH rebuilds are asynchronous.

### Results and decision

Eight final exported runs cover **29 views/configurations**: three-map
Compatibility sweeps, the strongest view/open-view controls with lower ray
budget, grass plus shadows, scenery-only culling targets, opaque-object
occluders, and Forward+. All 174 timing windows advance 96 normal rendered
frames, discard 32 warmup frames, and measure 64. Each condition uses three
windows per state in the order off/on/on/off/off/on.

| Selected case | Draws off → on | Native viewport CPU off → on |
|---|---:|---:|
| `bz2g`, obstructed opposite view, terrain, 512 rays/thread | 350 → 215 | 0.387 → 0.495 ms |
| Same view, 128 rays/thread | 350 → 238 | 0.385 → 0.398 ms |
| `bz2g`, open high view, terrain, 512 rays/thread | 182 → 182 | 0.247 → 0.441 ms |
| `bz2g`, opposite view, grass and shadows | 949 → 791 | 0.885 → 0.932 ms |
| `bz13h`, low view, terrain + opaque objects | 390 → 370 | 0.469 → 0.623 ms |
| Forward+, `bz2g` opposite view | 559 → 348 | 0.163 → 0.341 ms |

The default-ray terrain path adds **0.108–0.204 ms** of native viewport CPU time
in all 18 baseline Compatibility views. Lowering the ray budget approaches
break-even in the obstructed view but retains overhead in the open view.
Opaque-object occluders remove only three additional draws beyond terrain in
the fortress low view and none in its other two tested poses. Their script-side
assembly takes about 14 ms here, including texture readbacks; that excludes
background BVH construction and is not a zone-load benchmark.

The grass/shadow view shows a GPU saving, and targeting only placed scenery
removes 132 draws versus 158 when grass/terrain may also be culled. GPU time and
pre/post-render wall time vary substantially across runs, including variation
in a control view with unchanged draw counts. The data identifies a possible
benefit in obstructed, expensive scenes, not a stable gameplay FPS gain. No
other recognized game/editor render process was present at the runs' start/end;
this is not continuous load isolation or fixed CPU/GPU clocks.

**No production rollout is justified by this checkpoint.** Of the 29 settled
comparisons, 22 are byte-exact; all 29 off-state restorations are byte-exact.
Seven fortress cases differ by 1–18 pixels above 2/255 (maximum 27/255).
Their cause is unverified; do not transfer P3's separately reproduced nine-pixel
conclusion to them. The raw shadow counter remains zero even with shadows
enabled, so use image comparisons rather than that counter as shadow evidence.

Continuous camera motion, narrow openings, cave entrances, moving/fading
objects, deformation, real gameplay and actual Android/browser performance
remain acceptance work. Coarse conservative proxies and workload-based
selection may reduce the cost, but require evidence before implementation.
Keep logical/gameplay vision separate. With no general win established, the
next safe implementation priority can return to P5's remaining light/shadow
transition work; P4 should resume for a specific workload or device where it
has a demonstrated benefit.

### Reproduction details that matter

Use the existing exported `--tool` runner with `--render-thread safe`, isolated
XDG directories and the original game installation. Supported flags are
`--occlusion-map=bz2g`, `--occlusion-views=dense_opposite,center_high`,
`--occlusion-timing`, `--occlusion-rays=128`, `--occlusion-grass`,
`--occlusion-shadows`, `--occlusion-scenery-only` and
`--occlusion-opaque-objects`. The source defaults to `bz13h`, all six poses,
512 rays/thread, and no optional effects. Do not combine with `--scenery-batches`.

Two initial timing approaches were rejected. Setting VSync only on DisplayServer
is insufficient: GameData reapplies its startup options after three frames.
Disabling automatic rendering and using `force_draw()` is also invalid here:
Godot advances the frame counter used by occlusion hysteresis in its normal
[main render loop](/home/llm2x/Documents/EI/local/scratchpad/coop-performance-20261005/engine-profile/godot-5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/main/main.cpp:5086),
so forced draws alone can leave objects retained indefinitely. The final tool
sets the options too, measures normal pre/post draw signals, and verifies the
frame advance. Its wall metric is not interchangeable with P3's force-draw metric.

The probe freezes shader time with new shared Shader resources and restores
the original material shaders afterward. Earlier attempts to rewrite compiled
Forward+ shaders produced render-thread RID errors and leak warnings; those
runs are excluded. Final runs complete without script/render errors or RID-leak
warnings. Compatibility retains its known unsupported screen-space-AA warning.

The [evidence JSON](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/docs/validation/terrain-occlusion-2026-10-08.json)
contains source/export hashes, exact commands, per-window distributions, image
hashes, rejected attempts and the read-only integration check. Full receipts
and images are under the isolated QA `p4-occlusion` directory.

## P5, first stage: stable local-shadow selection

At this first-stage checkpoint, P4's production visibility changes overlapped
the other chat's investigation, so the independent change was the local-light
selection policy. The original
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
after the hold; shadow-strength fades and static/dynamic shadow-map reuse were
not implemented by this first step. The follow-up below adds Forward+ strength
transitions. The hold can intentionally delay a better but
still-visible challenger by up to two seconds; becoming ineligible or shrinking
the available budget takes precedence.

### Source and implementation locations

- Commit: `9bc5ce2` — `Stabilize local shadow selection across camera movement`.
- Reference: R0 [Source/point_shadow_policy.h:11](https://github.com/Ilufus/evil-islands-owned-renderer/blob/d529d14e9bf3c960833a9d9633786fc4588ec6d2/Source/point_shadow_policy.h#L11), `PointShadowPolicy` and `PointShadowScheduler::select`. Its two-second hold, 1.25 score hysteresis and four-unit distance hysteresis inform the adaptation. Upstream uses those policies for eligibility, scheduling and pressure retirement; this is a Godot selection adaptation, not a literal scheduler port. In particular, upstream's four-lamp work budget is **not** a four-resident-shadow limit. Our existing four-shadow cap is retained independently.
- [game/src/game/fx/local_lighting.gd:13](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/local_lighting.gd:13): policy constants and `_shadow_since` state.
- [game/src/game/fx/local_lighting.gd:382](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/local_lighting.gd:382): `_shadow_candidate`, `_select_shadows` and `_assign_shadows`.
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

## P5 follow-up: bounded shadow-strength transitions

Historical checkpoint `ea81497`; the subsequent Compatibility correction is
recorded in the next section. Forward+ fades enhanced fire, spell and lava shadows over 0.4 seconds.
At a full budget, the outgoing shadow fades out before its replacement starts
fading in: nominally 0.8 seconds for the complete handoff, plus scan/frame
granularity. Initial admission takes 0.4 seconds. At every intermediate step,
at most four local lights have `shadow_enabled`, including at most two lava
lights. An outgoing light still counts against this limit. This does not claim
that Godot immediately deallocates a disabled light's retained atlas slot.

Desired selections and admitted lights have separate, bounded weak-reference
tables. The two-second hold starts when a light is admitted, so waiting for a
slot does not consume its tenure. A cancelled replacement can reverse the
outgoing fade from its current opacity. Hidden/freed/queued lights release on
the next manager update; range/frustum rejection releases on the selection
scan. No-camera, option, world and pooled-lava changes cancel deferred writes.
Authored `shadow_opacity` is both the fade ceiling and part of the original
property snapshot. Turning enhancement off restores it, including when the
original light already cast shadows. External spell energy/lifetime ownership
is preserved.

At that checkpoint only Forward+ enabled this path. A zero-opacity Compatibility shadow still
uses a different additive pass from an unshadowed local light. The current
production shader's encoded colour correction cannot make the two paths
identical in these fixtures. Fading opacity to zero and then disabling the flag
would therefore introduce a brightness jump over ordinary lit surfaces.
Compatibility keeps the existing immediate selection exchange; the native
Mobile renderer also stays on that path pending validation. This local-light
gate is independent of the desktop continuous-sun policy described below.

### Source and implementation locations

- R0 [Source/point_shadow_policy.h:13](https://github.com/Ilufus/evil-islands-owned-renderer/blob/d529d14e9bf3c960833a9d9633786fc4588ec6d2/Source/point_shadow_policy.h#L13) defines `fade_seconds = .4f`. [PointShadowScheduler::select:275](https://github.com/Ilufus/evil-islands-owned-renderer/blob/d529d14e9bf3c960833a9d9633786fc4588ec6d2/Source/point_shadow_policy.h#L275) ramps retiring, moving, valid and overlay strengths, releasing retired slots at zero. The remake adapts the strength/retirement idea; it does not implement that renderer's static/dynamic caches or copy its scheduling budget as a resident limit.
- [local_lighting.gd:14](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/local_lighting.gd:14): duration; line 28 snapshots opacity; line 45 gates the backend. `_set_shadow_targets` at line 468 separates selection from admission; `_advance_shadows` at line 495 enforces both limits and updates opacity. `_release_shadow`/`_forget_shadow` and the existing lifecycle methods restore ownership correctly.
- [gfx.gd:388](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/gfx.gd:388): `set_local_shadow` keeps the actual shadow flag and Compatibility marker aligned. `light_code`, especially lines 481–490, is the existing local-light/pass correction to investigate before enabling GLES fades. It is not changed by this increment.
- Pinned Godot `5b4e0cb0f`: `drivers/gles3/rasterizer_scene_gles3.cpp:2076`, `drivers/gles3/shaders/scene.glsl:2996`, and `servers/rendering/renderer_rd/storage_rd/light_storage.cpp:1160` implement native opacity and distance-fade multiplication. Their inspected source hashes and absolute source root are in the evidence JSON. Native opacity is an available control, not proof of map caching or lower frame cost.
- [local_shadow_fades.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/local_shadow_fades.gd): actual-manager timing, budget, reversal, disappearance, lava reuse, original-property and process-order cases. `test_pass_boundary` diagnoses the renderer boundary; `test_rendered_fades` captures the real Forward+ transition using the production figure shader. The shared [local_shadow_selection.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/local_shadow_selection.gd) still checks ranking/hold policy separately, settling fades without advancing its explicit policy clock.

### Validation and remaining work

The exported Linux release passes 726 headless transition checks, 923 Forward+
checks and 737 checks on each Compatibility light budget (8 and 4). The state
machine is explicitly exercised on all three test configurations; only the
Forward+ rendered transition uses an enabled production fade policy. Existing
selection tests pass 377 headless checks and 418 checks on each GPU configuration.
That is 4,754 passing candidate checks, plus 418 in the frozen Compatibility
baseline. All five baseline/candidate Compatibility captures match byte for
byte. No installed build or physical device was used.

In the controlled 640×480 Forward+ fixture, an immediate left/right exchange
changes 47,267 pixels above 2/255, with a peak channel difference of 33/255.
The eight sampled 0.1-second fade steps peak at 8–11/255. Starting a replacement
causes zero immediate changed pixels; the settled result matches the direct
exchange exactly. A shadow-only caster moving during a half-strength fade
changes 19,844 pixels, demonstrating that the native map continues updating.
Carried-light captures also change, but that count includes ordinary lighting.
These are visual continuity measurements, not whole-game performance results.

| Zero-opacity flag transition | Changed pixels above 2/255 | Maximum channel difference |
| --- | ---: | ---: |
| Forward+, five lights | 0 | 0 |
| Forward+, thirteen lights | 0 | 0 |
| Compatibility budget 8, five lights | 220,150 | 39/255 |
| Compatibility budget 8, thirteen lights | 257,452 | 47/255 |
| Compatibility budget 4, thirteen lights | 244,080 | 43/255 |

Before GLES rollout, fix or replace the pass/light representation and repeat
the zero-opacity boundary test with multiple light counts, sun shadows and
terrain/figure materials. Do not mask that discontinuity by fading the light's
energy, which would change illumination. Full gameplay visual acceptance,
native Mobile/device testing, importance scoring and static/dynamic map reuse
remain separate work. The added per-frame bookkeeping visits at most four
admitted lights and four targets; no frame-time or VRAM improvement is claimed.

The reproducible exported commands, source/pack/image hashes, complete check
counts and read-only integration result are saved in
[local-shadow-fades-2026-10-08.json](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/docs/validation/local-shadow-fades-2026-10-08.json).
Raw runs and the isolated release are under
`/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa/p5-fades/`.
Use `--tool=/absolute/path/to/tools/tests/local_shadow_fades.gd`, the existing
isolated asset root and `--render-thread safe`; GPU runs must remain sequential.

## P5 follow-up: continuous Compatibility light-pass transitions

Desktop Compatibility now uses the bounded 0.4-second shadow fades too. The
prerequisite is a shader correction: enabling a zero-opacity shadow must not
change the underlying illumination. This is a quality improvement with a
measurable GPU cost, **not a shadow-cache or FPS optimization**.

Android/web Compatibility retain the existing shader and immediate shadow
exchange by default. `--local-shadow-fades` opts into the corrected shader and
fades for device comparisons; `--no-local-shadow-fades` selects the old
Compatibility path, including on desktop, and wins if both are supplied.
These switches are user arguments after `--`. They affect Compatibility only.
Forward+ keeps its previously validated fade policy; native Mobile remains
unvalidated. Sun aiming is a separate policy: desktop stays continuous, while
Android/web retain the replaceable shimmer/cost fallback requested by the user.

### Why the correction is needed

Godot's GLES base pass and each shadowed-light pass are encoded separately,
then added in stored sRGB. The previous remake shader approximately corrected
one shadow pass, but its unshadowed lights accumulated differently. Fog,
emission and other lights made that discrepancy large even at zero shadow
opacity. Applying an opacity fade alone would still finish with a brightness
jump when the shadow flag changed.

The corrected path gives each enhanced local light the same encoded addition
in either pass. It includes that light's surface highlight/leaf transmission,
captures fragment emission and the renderer's half-packed fog, and compensates
the base pass before Godot performs its final fog/encoding operations. It uses
the pinned GLES encode/inverse pair, not the remake's clamped colour helpers.
Fully opaque fog bypasses the inverse; zero fog avoids unnecessary conversion
round trips. The original non-local lighting arithmetic is retained.

This establishes consistent per-light additions, **not pixel preservation of
the previous enhanced-light look**: multiple unshadowed enhanced lights can now
produce brighter results. It assumes the game's current linear tone mapping,
exposure 1 and original environment. Revalidate before changing that pipeline.
It does not alter light energy, create extra light nodes, enlarge the four-light
shadow budget, or cache native maps. The marker still follows `shadow_enabled`;
native routing also requires an allocated shadow atlas entry. Both the normal
2048 atlas and the constrained 1024 atlas are covered, but absent atlases and
alternate environment/reflection-probe pipelines are outside this acceptance.

### Source and implementation locations

- Upstream motivation remains R0 [PointShadowPolicy::fade_seconds and PointShadowScheduler::select](/home/llm2x/Documents/evil-islands-owned-renderer/Source/point_shadow_policy.h:13), including retirement at zero strength around line 275. This pass correction is a Godot adaptation discovered while applying that idea; it is not an upstream implementation copied into GDScript. Upstream's four-lamp value is a per-frame work budget, not a residency cap.
- [local_light_shader.gd:9](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/local_light_shader.gd:9) owns the desktop/device gate and explicit overrides. `COMMON`, `CAPTURE`, `BEGIN` and `END` below it contain the transfer functions, fragment state and consistent accumulation. Keep the fog packing and emission polynomial aligned with the engine when upgrading Godot.
- [gfx.gd:203](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/gfx.gd:203) inserts the helpers only when enabled; `_function_tail` captures after the complete fragment body, including optional fog rewrites. [light_code:441](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/gfx.gd:441) surrounds each light contribution and preserves the previous generated branch on other paths. Ground-contact lighting still rewrites the complete composed light function.
- [local_lighting.gd:45](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/local_lighting.gd:45) enables fades with the corrected shader. The prior weak-reference state machine, restoration, two-second tenure and four-total/two-lava limits are unchanged.
- Pinned Godot [scene.glsl:2393](/home/llm2x/Documents/EI/local/scratchpad/coop-performance-20261005/engine-profile/godot-5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/drivers/gles3/shaders/scene.glsl:2393) packs fog; emission conversion follows. Its base output encodes at line 2798; the separately fogged additive output encodes at line 3070. [tonemap_inc.glsl:14](/home/llm2x/Documents/EI/local/scratchpad/coop-performance-20261005/engine-profile/godot-5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/drivers/gles3/shaders/tonemap_inc.glsl:14) defines the actual conversions. [rasterizer_scene_gles3.cpp:1353](/home/llm2x/Documents/EI/local/scratchpad/coop-performance-20261005/engine-profile/godot-5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/drivers/gles3/rasterizer_scene_gles3.cpp:1353) selects the separate pass using shadow availability. Exact source hashes are in the evidence JSON.
- [local_light_passes.gd:10](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/local_light_passes.gd:10) renders the actual composed production shaders in 18 situations. Its `--light-pass-cost` mode at line 75 measures a larger static fill workload. [local_shadow_fades.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/local_shadow_fades.gd) now exercises production GLES transitions and the legacy override. [material_shader_options.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/material_shader_options.gd) uses an explicit SubViewport and forced draw to compile the driver's real programs while keeping the main window minimized.

### Acceptance and cost

On the exported Linux build / RTX 3090 / NVIDIA 580.178.04, all 18 boundary
situations pass at both per-object light limits (8 and 4): 155 checks each.
They cover single/five/crowded lights, sun shadows, material highlights,
original point lights, emission, partial/dense/full fog, a bright fog boundary,
transparency, glow, original lighting without locals, terrain lighting, and the
1024 shadow atlas. Every flag transition stays within 2/255 per channel, with
zero pixels above that threshold; only glow reaches 2/255. The frozen `ea81497`
export fails 16 of those 18 situations as the intended negative control. The
five-light boundary falls from 220,150 pixels above 2/255 / peak 39/255 to zero
such pixels / peak 1/255.

The final transition suite passes 726 headless checks, 924 on each GLES light
limit, 923 on Forward+, and 737 in the explicit legacy GLES mode. Existing
selection checks pass 418 times in that legacy mode; all five selection
captures match `ea81497` byte for byte. All 18 Forward+ fade captures also match
that checkpoint exactly, as do both original/no-local controls. The shared
ground-contact lifecycle test passes 35 checks. All 108 material/shader option
switches render on each backend, with 362 checks passing per backend. Including
the two candidate cost runs, the final exported candidate passes **5,769 checks**.
The 16 expected failures in the frozen negative control are recorded separately.
The final GLES shader-option run takes 173 seconds; the Forward+ run reuses its
shader cache and takes 7.8 seconds. These compilation-validation timings are
not a matched cold-start performance comparison.

For the new GLES lighting model, the immediate left/right exchange peaks at
65/255; eight sampled 0.1-second fade steps peak at 12–25/255, without a jump
when selection starts, and settle to exactly the direct-exchange endpoint.
A shadow-only moving caster changes 17,279 pixels during a partial fade, so
native shadow-map updates remain live. These are controlled 640×480 shader
fixtures, not a full-map artistic review or physical-device acceptance.

The static cost probe uses 1280×960, 64 warmup draws and 96 measured draws per
case. The table averages the two per-run GPU medians in baseline/candidate/
candidate/baseline order. All corresponding draw counts remain equal.

| Scene | Previous GPU time | Corrected GPU time | Added time |
| --- | ---: | ---: | ---: |
| No enhanced local lights | 0.078 ms | 0.079 ms | about 0.001 ms |
| Five local lights | 0.368 ms | 0.425 ms | 0.057 ms |
| Crowded local lights | 0.420 ms | 0.571 ms | 0.152 ms |
| Five lights with fog | 0.441 ms | 0.500 ms | 0.059 ms |

The crowded GPU cost remains about 36% higher in this deliberately small
fill-heavy fixture. Removing redundant conversion round trips reduced the
earlier candidate's sampled cost, but does not make the correction free.
Viewport CPU and forced-draw wall timings are recorded separately; neither
establishes a whole-game FPS gain. The probe explicitly submits static draws:
minimized X11 windows suppress automatic rendering, so initial attempts that
waited for `frame_post_draw` produced no timing samples and were discarded.
Do not use that forced-draw approach for frame-count-dependent occlusion tests.

Keep constrained rollout opt-in until Android/browser GPU cost, driver shader
limits and full-scene lighting are checked. The four-light-limit desktop run
and 1024 atlas case do not substitute for device testing. Native Mobile,
importance scoring, static/dynamic map caching and broader V1 lighting
acceptance remain separate priorities. The Retroid and installed builds were
not used. Reproduction commands, exact check counts, image/source/pack hashes,
shader-option compilation results, discarded runs and the read-only integration
check are in
[local-light-passes-2026-10-08.json](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/docs/validation/local-light-passes-2026-10-08.json).
Raw evidence and frozen exports are under
`/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa/p5-compat-light/`.

## P5 follow-up: range and strength aware shadow selection

The selector now considers a local light's range, linear peak colour, energy
and authored shadow opacity. A dim near light no longer automatically outranks
a brighter or wider light slightly farther away. Zero-contribution fire/spell
lights and lava banks cannot keep a reserved slot. This changes shadow
admission only: light energy, colour, position, range and effect lifetime stay
with their existing owners. The four-total/two-lava limits remain unchanged.

R0 [PointShadowScheduler::select:283](/home/llm2x/Documents/evil-islands-owned-renderer/Source/point_shadow_policy.h:283)
weights radius and peak colour strength when ordering work/allocation requests.
Its formula is `radius * peak_colour / (1 + distance / max(radius, 1))`;
its scheduler does not impose our four-resident-light cap. The remake adapts
that idea to its existing squared-distance ordering instead of copying its
allocation policy. Lower score is better:

```text
score = (1 + previous_distance_score)
        / (range² * linear_peak_colour * energy * authored_shadow_opacity)
```

Fire/spell distance remains `focus_distance² + 0.15 * camera_distance²`;
lava retains its focus-distance preference. Nonpositive contribution is
ineligible. The one-unit numerator floor prevents an arbitrarily weak light
at the exact focus from receiving an unbeatable zero score. Existing two-second
tenure and 1.25 hysteresis still apply to eligible lights. Authored opacity is
read from the original property snapshot, **not the animated fade value**:
newly admitted zero-opacity shadows and partial fades must not disqualify
themselves. Zero contribution is a hard eligibility loss on the next 0.25-second
selection scan, so it does not keep waiting out its old tenure.

Implementation is in [local_lighting.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/local_lighting.gd):
`_shadow_score`, `_assign_shadows`, `_shadow_candidate`, `_in_view` and
`_scan_lava`. Both scans now capture the current camera position/frustum once,
reusing that snapshot only inside their synchronous loop. It is not a persistent
camera cache; every new scan observes camera motion and projection changes.
This removes repeated frustum extraction while paying for the richer ranking.

### Independent acceptance

[local_shadow_importance.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/local_shadow_importance.gd)
tests actual manager admission for brightness, colour, range and authored
opacity; zero-contribution release; lava reservation; unchanged light
properties; zero/partial transition opacity; and independent ±8% flutter after
tenure expires. Existing selection/fade suites retain their timing, ownership,
restoration, moving-caster and budget checks. The eight-second equal-light
camera oscillation still produces three selected-set changes. A new camera
rotation/return case checks that the per-scan frustum is refreshed.

The GPU comparison measures each light separately: hold its native shadow/pass
flag constant, capture opacity 0 and opacity 1, and sum the absolute RGB change.
It then asks the actual manager which four lights to retain. This measurement
does not use the proposed score. Both frozen `1bb7503` and the candidate render
the same single-light controls; their selected sets differ.

| Controlled scene / renderer | Previous selected share of measured shadow signal | Weighted selection |
| --- | ---: | ---: |
| Brightness, Compatibility limit 8 | 3.9% | 96.1% |
| Range, Compatibility limit 8 | 1.7% | 98.3% |
| Brightness, Forward+ | 2.0% | 98.0% |
| Range, Forward+ | 0.8% | 99.2% |

Compatibility's four-light-limit cases also select the strongest measured
shadow. Individual zero-opacity flag changes stay within 1/255 on GLES and
are exact on Forward+, separately recorded from the shadow-strength signal.
These figures describe two deliberately diagnostic scenes, not global visual
quality percentages. The heuristic cannot determine whether a bright light
actually has visible receivers/casters, whether a wall occludes it, or which
other light a geometry's native limit excludes. Full-map artistic/device
acceptance and caster-aware selection remain open.

Transition fixtures now use three stronger anchor lights so that their
selection remains stable under the new weighting. One anchor is outside the
receiver's light range: otherwise the native four-light list can omit the
outgoing torch and make its first fade leg invisible. Both fade legs remain
visible in the final fixture. That superseded fixture failure is recorded in
the evidence, rather than weakening the per-step fade assertions.

The `--shadow-importance-cost` mode measures the actual selection method with
16, 64 and 128 candidate lights. It excludes gameplay, renderer submission and
shadow-map work. The richer score alone added about 0.10 ms to the old 0.74 ms
128-light scan on this desktop. Per-scan frustum reuse removes most of that
overhead. The final baseline/candidate/candidate/baseline comparison averages
two per-run medians (64 warmup scans, 256 measured scans each):

| Candidate lights | Previous scan | Final scan | Added CPU time per scan |
| --- | ---: | ---: | ---: |
| 16 | 78 µs | 89.5 µs | 11.5 µs |
| 64 | 363 µs | 373.5 µs | 10.5 µs |
| 128 | 731.5 µs | 748 µs | 16.5 µs |

The final exported candidate passes **7,354 checks**: 318 headless importance
checks, 358 importance checks on each of Compatibility limits 8/4 and Forward+,
384 headless and 425-per-backend selection checks, 726 headless fade checks,
924/924/923 rendered fade checks, 737 legacy-Compatibility fade checks and 494
checks across the two candidate timing runs. All 44 single-light/control
images shared with the baseline (22 on each desktop renderer) match exactly.
The old selector produces 11 expected headless failures and 13 on each rendered
baseline run; these are recorded separately from candidate success.

No GPU/frame-rate saving is
inferred from selecting more useful lights: larger selected ranges can also
include more casters, even with the same number of shadow-enabled lights.

Exact check counts, final selector timings, frozen-export/source hashes,
negative controls, image comparisons and the read-only integration check are in
[local-shadow-importance-2026-10-08.json](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/docs/validation/local-shadow-importance-2026-10-08.json).
Raw runs and exported binaries are under
`/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa/p5-shadow-importance/`.
Compatibility's Android/web fade gate, desktop sun policy, native Mobile fade
policy and all visual-option defaults are unchanged. No character, co-op,
zone-transition, installed-build or physical-device changes are included.

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

Commit: `39b4b7e` — `Keep desktop sun aiming continuous across renderers`.

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

## V1: validate the terrain surface before blending objects

This is a **prerequisite diagnostic, not an enabled ground-contact effect**.
[tools/benchmarks/ground_contact_surface.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/benchmarks/ground_contact_surface.gd)
compares a shader lookup with the actual rasterized terrain triangles, including
loose snow/sand and the installed footprint geometry. It runs externally against
the frozen `p6-export/` Linux release; no production source changed in this step.
The upstream design remains R1 `Source/contact_blend.h` and
`Renderer::update_contact_blend_maps`, as linked in the main audit's V1 section.

Three implementation findings matter:

1. `EITerrain.height_at` is a gameplay-oriented bilinear query. The drawn land
   also has signed-byte horizontal vertex offsets (`_read_vertices`, `land_xy`)
   and two particular triangles per cell (`_mesh_arrays`: CBA and BCD). In the
   tested 8 m sloping patches, the bilinear control averages approximately
   9–13 cm from the rendered surface. Do not use it directly for the contact band.
2. The first enclosing triangle is insufficient. Some authored offsets fold
   triangles over each other. On the selected `bz10k` snow patch, first-hit
   selection fails the 2 mm threshold at **239 pixels**, reaching approximately
   **1.11 m** error. The diagnostic searches both triangles in each of the nine
   possible nearby cells and selects the highest deformed surface, matching the
   top-down depth buffer. This establishes a correctness reference; doing all
   those fetches on every object fragment is not yet a production cost decision.
3. Soft-ground lookup must reproduce the geometry that is currently installed.
   `SoftGroundDeform._subdivide` uses 16-way subdivision in each original
   triangle's barycentric coordinates. The shader applies the loose profile and
   track height at those vertices, then rasterization interpolates them. Sampling
   a continuous height formula directly at the fragment is different. Pending
   tiles must remain coarse until their mesh job is installed; cleared/expired
   tiles must return to the coarse representation. The original tile coordinates
   also interpolate over displaced triangles, so world xy alone is not the
   correct authored atlas UV.

The probe reads the original atlas/soft-profile shader helpers from
`EITerrain.TERRAIN_SHADER`, while the reference side renders the real installed
`EITerrainSector._parts` meshes. It compares height inside the mesh fragment
shader against its own interpolated world position. The **2 mm pass/fail flag is
computed on the GPU**; read-back RGB values provide approximate statistics only.
This avoids false height failures caused by packing a large height across colour
channel boundaries. The separate UV/albedo pass compares the rasterized mesh with
a flat query surface. Captures use a floating target and calibrate colour space.

Validation on NVIDIA RTX 3090, Godot 4.7 `5b4e0cb0f`, exported Linux release:

- **158 checks pass on Compatibility and 158 on Forward+.** There are 16 terrain
  states per renderer and 1,032,250 covered height samples per renderer. No query
  coverage failures and no sampled height errors above 2 mm remain.
- Maps: `bz2g` grass at `(121.35, 31.45)`, `bz10k` snow at `(45.35, 111.45)`,
  `bz13h` authored sand/type 3 at `(52.35, 21.45)`. Cases cover original and padded
  atlases, loose material, queued-but-not-installed footprints, installed tracks,
  fading tracks and clear/restore. Type 12 is not represented by these maps.
- A separate no-tracks control proves the footprint field affects the rendered
  reference: 1,309 snow pixels and 556 sand pixels exceed 2 mm without the track
  query. Fading reduces those counts to 1,131 and 431 on both backends.
- UV differences stay below 2/255. Painted albedo passes the diagnostic's
  **99th-percentile** threshold of 2/255, but is **not pixel-identical**. The
  original sand patch has 253 changed pixels on Compatibility and 256 on
  Forward+, with peak differences about 0.188 in an RGB channel. Shader
  derivatives/filtering across triangle boundaries still need investigation.
- Three subpixel holes in the installed dense sand geometry appear on both
  backends. The probe reports them separately, excludes background from the
  height comparison, and does not call them query coverage failures.

Machine-readable results and the exact script SHA-256 are retained in
[docs/validation/ground-contact-surface-2026-10-08.json](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/docs/validation/ground-contact-surface-2026-10-08.json).
QA logs are `ground-contact-surface-gl.log` and
`ground-contact-surface-forward.log`. Raw reports/captures use `ground-surface-*`
and `ground-contact-surface-*.json` in the isolated QA user-data directory.

At the `4915d18` diagnostic checkpoint, the remaining work was:

- Move the validated sampling into shared production helpers, and resolve the
  albedo edge differences. The probe compares painted albedo, not the full
  sharpened/relief/macro/rain/light response.
- Share footprint GPU storage and installed-tile state per world. The probe's
  `surface_data` copies existing **CPU** images into a diagnostic texture array;
  it does not read textures from the GPU, but that duplicated storage is not the
  intended production implementation. Preserve job generations, water changes,
  sector eviction, option toggles and world teardown.
- Bind only eligible rigid scenery. Keep units, equipment, portraits and UI
  outside the effect. Use the actual mesh bounds/transform for a bounded contact
  band; test small props, long walls, slopes, tile/sector borders and moving
  objects/cameras. Preserve original alpha and CameraFade's material lifecycle.
- Retain P3's sharing where possible. Do not make a unique material per placement
  merely to bind the same terrain. Keep world textures out of global figure
  caches, and avoid per-frame updates to hundreds of material copies.
- Blend the ground response without multiplying it by the object's original
  diffuse/emissive tint. Add GPU tests for a white ground under a red/dark object,
  unchanged upper surfaces, shadows and local lighting.
- Measure shader/sampler cost before setting defaults. No Android/web, camera
  motion, moving-water, full-map performance or completed V1 quality claim is
  established by this diagnostic.

## V1: opt-in scenery blend and shared footprint storage

A first production path is now implemented in this branch. **It is experimental
and defaults off on every platform**, including desktop. It has not been merged
into the active release or installed. The existing desktop continuous-sun policy
and constrained-device held-sun fallback are unchanged by this increment.

The reference is R1
[Source/contact_blend.h](https://github.com/Ilufus/evil-islands-owned-renderer/blob/0092dc6e1d7c4aab3f74644a79e9bfca11ecf293/Source/contact_blend.h).
The bounded contact height, irregular edge, folded ground projection and mixing
of completed mesh/ground colours are adapted from its helpers. Our terrain
lookup, Godot lighting integration, material ownership and shared deformation
storage are remake-specific; this does not port their D3D11 renderer.

### Implementation map

- [ground_surface_shader.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/ground_surface_shader.gd)
  contains the common atlas/rotation/border and loose-ground sampling code,
  plus `QUERY_SHADER`. The latter searches both triangles of nine cells, selects
  the highest drawn surface, and reconstructs only **installed** dense tiles.
  Its triangle Jacobian supplies texture gradients without taking derivatives
  across unrelated UV owners. Internal runtime loop bounds remain 9 cells and
  3 vertices; they are not quality settings. The benchmark turns only diagnostic
  `query_*` booleans into uniforms for negative controls.
- [terrain.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/ei/terrain.gd)
  uses those common helpers. `_build_surface_data` fills previously unused B/A
  channels of the existing RGBAF tile texture with loose thickness/compression
  (snow 0.20/0.30, packed snow 0.075/0.12, sand 0.008/0.025). This adds no texture
  allocation and removes repeated type branches from shader queries. Water-level
  and rain-cover changes refresh contact parameters after land uniforms change.
- [soft_ground_field.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/soft_ground_field.gd)
  owns one shared `Texture2DArray`, an installed-tile RGF texture, and an RF clock.
  Capacity grows 1/2/4/8 layers; it reuses the existing CPU sector images rather
  than copying them. The texture RID survives growth, vacancy reuse and clearing.
  Empty storage shrinks to a 1×1 placeholder. A full eight-layer array is 32 MiB;
  three or five active sectors can retain spare capacity, so this is not a claim
  of lower total memory than the previous individual textures.
- [soft_ground_deform.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/soft_ground_deform.gd)
  allocates/reuses field layers, updates only changed layers, and publishes a
  sector's layer/dense flags when `_apply_mesh` installs its geometry. A queued
  tile remains coarse. Eviction, capacity reset, clear and teardown remove the
  installed state. The original worker generations and mesh/shadow restoration
  remain in place. One shared clock avoids updating every contact material per
  frame; this path performs no GPU readback.
- [ground_surface_data.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/ground_surface_data.gd)
  owns a world's authored vertex/normal textures, conservative height bounds,
  and a weak terrain reference. It binds the existing land atlases, tile/cell
  data, water/rain values and shared field. With no active deformation it uses
  an empty field. These textures are created lazily when contact is enabled.
- [ground_contact_shader.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/ground_contact_shader.gd)
  extends the original object/foliage shaders. Transformed mesh bounds limit the
  band to 1/8 of vertical size, capped at 0.4 m; reach varies with face direction,
  noise and the actual ground colour. A conservative height rejection and
  30–45 m distance fade bound work. The strip follows slopes and deformation,
  folds up walls, and fades away under water. It includes the ground's bounded
  sharpening, macro variation, wet-bank/rain colour and compacted-track darkness.
  Ground lighting is mixed after figure diffuse/emissive modulation. Compatibility
  needs explicit sRGB conversion for the additional fragment-to-light colour and
  a finite albedo carrier for zero texture channels; rendered tests caught both.
- [ground_contact.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/ground_contact.gd)
  owns weak mesh registrations and per-world material variants keyed by original
  base material plus exact local bounds. `refresh` runs after option listeners,
  preserves active camera fade amounts, and restores the exact original material
  when disabled. World-bound entries are removed from CameraFade's otherwise
  global strong caches. Teardown releases the world textures.
- [map_scene.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/ei/map_scene.gd)
  calls `GroundContact.attach` only for placed records whose kind is not `UNIT`.
  Headless workers skip this visual registration. [figure.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/ei/figure.gd)
  marks eligible raw object/foliage shader sources; regular figure caches never
  receive world textures. Characters, equipment and portraits are not registered.
- [gfx.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/gfx.gd)
  applies the extended light composition only to `EI_GROUND_CONTACT` variants.
  Other materials retain the original light source text. The independent option
  is `gfx_ground_contact` in [game_data.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/ei/game_data.gd),
  group 13, row 11. Saved explicit choices win; defaults, Original look and
  automatic/platform settings leave it off.

### Validation and limits

The exported Linux release is in the isolated QA directory's `v1-export`.
[ground-contact-implementation-2026-10-08.json](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/docs/validation/ground-contact-implementation-2026-10-08.json)
retains the commands, source hashes, backend results, resource counts and timings.
The earlier surface-only JSON remains a historical checkpoint.

Exported release results, all with zero failures:

| Check | Compatibility | Forward+ |
|---|---:|---:|
| Shared field GPU lifecycle | 152 | 152 |
| Contact ownership and rendered band | 35 | 35 |
| Authored surface/profile query | 158 | 158 |
| Three maps, near/far off/on/off | 30 | 30 |

Additionally, 3,014 headless worker/mesh checks and 362 shader-option checks
pass: **4,126 checks total**. The surface test covers 1,032,250 height pixels per
backend with no query misses or errors above 2 mm. Three existing subpixel sand
raster holes are reported separately. No other game process was present at the
start of any final validation case. The image review included the corrected
snow camera and the grass/tree and sand/building comparisons.

The final 800×600 map samples add about 0.24–0.62 ms of viewport CPU work on
Compatibility, and about 0.02–0.06 ms on Forward+ (on minus the mean of the two
off captures). On-state GPU medians range 1.77–2.14 ms on Compatibility and
0.67–1.84 ms on Forward+, with visibly variable off medians. Read the paired
numbers in the JSON; this effect costs work even where its distant contribution
is small. No overall speedup is claimed.

The updated [ground_contact_surface.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/benchmarks/ground_contact_surface.gd)
uses the **production shared field** for query reads. Its real-mesh vertex pass
retains the old type-ID displacement function as an independent oracle for the
new packed profiles. Analytic gradients reduce original sand's colour outliers
from 253 to 8 pixels in the sampled patch, and padded grass from 69 to zero.
Sparse edge/raster ownership differences remain; this is not pixel identity.

[soft_ground_field.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/soft_ground_field.gd)
keeps one shader's textures bound while growing, updating, retiring, reusing,
clearing and rebuilding storage. [ground_contact.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/ground_contact.gd)
checks sharing/isolation, fades, wind/water parameter propagation, cache cleanup,
opt-in defaults, rendered upper surfaces, small-prop bounds, underwater rejection,
alpha holes, and final ground colour under dark/red/emissive object materials.
The existing `soft_ground_mesh` worker regression and expanded
`material_shader_options` composition/option/fog checks also run.

[ground_contact.gd (map benchmark)](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/benchmarks/ground_contact.gd)
renders grass/snow/sand maps `bz2g`, `bz10k`, `bz13h` at near/far cameras in an
800×600 viewport, with fixed sun shadows and off/on/off captures. Camera height
is kept above the terrain at its position. Do not use the earlier snow capture
made from inside the hillside as visual acceptance evidence. Draw counts and
original pixels restore exactly in the final fixtures. Contact variants increase
material counts: the tested Compatibility maps register 668/268/725 parts,
using 99/72/133 contact materials versus 18/3/13 eligible base materials.
They share identical bounds; this is still a cost relative to the P3 base path.

**Do not enable by default yet.** Initial Compatibility warmup in this fixture
was about 64.2 s; consolidating displaced vertex work and storing profiles in the
existing tile data reduced a subsequent first-use observation to about 16.4 s.
These are observed 24-frame warmups after shader changes, not a controlled driver
cache-flush benchmark. Warm cached runs are much faster. Cold preparation is
still unacceptable as an automatic new effect. The sampled viewport CPU/GPU
costs are retained rather than converted into gameplay FPS claims; GPU clock/load
variation matters, and one earlier exploratory run overlapped the other chat's
GPU test. The exported validation records other game processes at each start.

Further work before treating V1 as finished:

1. Reduce first-use preparation and measure cold/warm behavior on actual target
   hardware. Compare fixed versus runtime query loops, shader variants with
   deformation absent, and a reusable GPU surface cache if justified. Preserve
   the exact folded-triangle/dense-tile result and the independent oracle.
2. The band uses base/interpolated ground normals and native light channels.
   It does **not** yet reproduce all painted/triplanar relief normals, track-normal
   glints, wet specular response or underwater vertex-light interpolation at a
   shoreline. Broader local-light, wet-weather and animated-camera acceptance
   remains; do not describe the copied ground as a complete terrain BSDF.
3. Extend visual coverage to rotated/scaled moving props, long walls across
   sectors, track crossings at scenery roots, and representative maps/camera
   angles. Existing shader/field tests are not an all-assets gameplay test.
4. No physical Android/web quality, compilation, thermal or frame-time result
   is established. Both platforms remain off by default, as does desktop until
   the remaining cost/quality work warrants changing it.

## V1: reduce duplicate surface-query expansion

The follow-up changes only
[ground_contact_shader.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/ground_contact_shader.gd)
and its internal parameter binding in
[ground_surface_data.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/fx/ground_surface_data.gd).
`contact_prepare` now uses a single shader call site for its two surface queries.
The runtime bound is always two; it is a compiler control, not a user quality
setting. The folded strip, fallback to the original query when the strip leaves
the map, early rejection, all colour samples and final lighting remain. This
avoids expanding the large displaced-triangle search at both call sites.

[ground_contact_preparation.py](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/benchmarks/ground_contact_preparation.py)
compares two frozen Linux exports on Compatibility, first with empty Godot and
NVIDIA driver caches and then with the same caches warm. It isolates all XDG
and driver directories, records commands/build hashes/cache counts/captures,
and checks for other game processes before each run. `--resume` completes an
interrupted comparison only if the map, benchmark, build and completed-run
sequence still match; cold caches must be empty and warm cache counts must
match the preceding cold run. Interrupted runs that changed caches need a new
output directory. The wrapper does not measure a pure compiler duration: the
reported on-state warmup includes 24 rendered frames.

The retained projection-only change measured **16,614 ms → 12,673 ms** in the
initial fresh-cache Compatibility grass sample (about 24% less). A separate
six-sample colour loop lowered this further to 8,560 ms, but was rejected after
alternating warm runs exposed a larger GPU cost. On the same RTX 3090 scene:

| Variant | Near-view GPU median, two runs | Far-view GPU median, two runs |
|---|---:|---:|
| Committed baseline | 1.915 / 1.996 ms | 1.900 / 1.983 ms |
| Retained projection loop | 2.077 / 2.074 ms | 0.685 / 0.696 ms |
| Rejected projection + colour loops | 2.403 / 2.362 ms | 1.923 / 1.934 ms |

All six alternating runs had no other game process at start or end and identical
capture hashes. The retained change still has a small near-view tradeoff, and
the far-view saving is specific to this sampled scene/driver. It is not a
whole-game FPS claim. A five-tap loop with a separate mean also failed to improve
that near-view cost in a follow-up diagnostic; its headless background jobs are
recorded, so its cold CPU preparation is not used as a controlled comparison.
**Defaults remain off**: 12.7 seconds is still too costly to enable automatically,
and no Android/web result is established.

The selected candidate passes 362 headless shader-option checks, 35 contact
ownership / rendered-band checks on each backend, and 30 map checks on each
backend: **492 checks, zero failures**. The selected candidate's map captures
are compared with frozen baseline captures: **36 byte-identical PNGs**, grass,
snow and sand × near/far × off/on/restored on Compatibility and Forward+.
This exercises the detail sampler; the focused rendered-band fixture also runs
with detail disabled. Query math, shared texture storage and worker code are
unchanged, so their earlier tests were not repeated. Some broad correctness
runs overlapped unrelated tests; their timings are retained for diagnosis and
are not a controlled runtime performance comparison.

Frozen exports remain under the isolated QA directory: `v1-export` is the
committed baseline, and `v1-preparation/export` is the selected projection-only
candidate. `export-taps` and `export-five` are rejected experiments, not the
current source. The initial cold-run logs, alternating warm comparison, selected
validation, source/pack hashes and integration check are retained in
[ground-contact-preparation-2026-10-08.json](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/docs/validation/ground-contact-preparation-2026-10-08.json).
The broader lighting, animated-camera, cross-sector prop and physical-device
requirements listed above remain open.

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
The P3 probe is a standalone benchmark only (commit `3855cc4`). P5 changes
`local_lighting.gd` and, in the Compatibility follow-up, `gfx.gd` and the new
`local_light_shader.gd`, plus their regression fixtures and documentation.
The P6 comparison is a standalone benchmark. The subsequent user-directed
default correction changes only sun policy/setup and menu sun aiming, plus its
test; it does not modify character visibility or zone-transition code.
The V1 surface probe was standalone. The subsequent opt-in path adds the modules
above and small hooks in `figure.gd`, `map_scene.gd`, `terrain.gd`, `gfx.gd`,
`game_data.gd`, graphics defaults and `soft_ground_deform.gd`. It does not modify
character/zone-transfer ownership, controls, combat or camera implementation.

The P3 runtime adds only the new manager/watch/light-policy modules and small
hooks in `map_scene.gd`, `camera_fade.gd` and `ground_contact.gd`, plus tests and
the benchmark. It preserves individual object nodes and does not touch the
other chat's newer creature visibility or story/co-op effect changes.

The latest read-only `git apply --check` includes all production/tool changes
from this branch's base through the P5 importance-ranking checkpoint. It passed
against active committed HEAD `433d5d97588cfd775fe342bd8544e71df9c27871`, including
uncommitted VM, session, camera-rig and slave-camp test changes. Its HEAD, status
and hashes of all 59 touched/dirty files were unchanged. **No patch was applied.**
The result and exact target state are in the P5 importance validation JSON above.
`game_data.gd` is shared by earlier commits: preserve its newer control/options
changes when integrating. Recheck before integration because that checkout is
still changing. Do not message or alter the other chat without human authorization.

## Next work in the established order

1. **P3 static scenery batching:** the opt-in live manager, complete-light guard,
   movement/fade lifetime and real-map validation are now implemented above.
   The nine-pixel residual is reproduced by the unchanged-renderer control.
   Desktop timing does not establish a net gain despite fewer draws; keep this
   experimental. Finish long gameplay/device acceptance and measure management
   cost against saved submission time on actual Android devices and browsers
   before rollout. Preserve the
   explicit material-change notification contract and logical mesh consumers;
   do not replace this with a naive MultiMesh regrouping pass.
2. **P4 occlusion:** the native terrain/opaque-object diagnostic above now
   measures hidden work. No general desktop gain or complete visual acceptance
   is established. Resume for a specific expensive obstructed scene/device;
   preserve gameplay visibility and validate motion, thin openings, fades,
   deformation and shadows before integration. Do not repeat the forced-draw
   timing approach or assume standard web templates include native occlusion.
3. **P5 local shadows, then P6 directional stability:** stable selection and
   bounded Forward+/desktop Compatibility strength transitions are implemented.
   The GLES pass discontinuity is corrected, with a measured GPU tradeoff;
   Android/web retain the existing path until device acceptance. Range/strength
   ranking and per-scan frustum reuse are now implemented. Full-map/device and
   caster-aware selection acceptance, native Mobile fades and cached map updates
   remain separate work.
   For P6, identify actual shimmer/redraw cost and renderer capabilities
   before changing cascade settings or planning engine-level projection reuse.
4. **C1 character batching/skinning:** keep as an isolated prototype until the
   main character/gameplay changes settle. The active remake still animates rigid
   figure parts. Converting to a skinned mesh was an author suggestion, not an
   implemented upstream feature or a demonstrated speedup.
5. **Visual track:** V1 ground-contact blending, V4 water interaction, V2 biome
   ground cover, then the remaining audit features. V1 now has shared production
   storage and an opt-in scenery blend, with the validation and limitations above.
   Resolve cold preparation and finish its lighting/visual acceptance before
   enabling defaults. No visual effect was silently enabled in this batch.
