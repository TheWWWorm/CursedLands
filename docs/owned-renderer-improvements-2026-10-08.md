# Owned renderer adaptations — 8–9 October 2026

Original renderer worktree: `/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008`

Original branch: `improve/owned-renderer-wounds-textures`

Starting commit: `3172ede12a5f41b0182c34a70b5eeda787c95e52`

The source audit and priorities are in
[OWNED_RENDERER_IMPROVEMENT_HANDOFF.md](/home/llm2x/Documents/EI/OWNED_RENDERER_IMPROVEMENT_HANDOFF.md).
**Active follow-up — 9 October 2026.** The user resumed the larger renderer and
gameplay goal. Continue on `fix/catacomb-coop-deck` in
`/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo`.
The earlier river-current checkpoint is `eda826d`; new checkpoints below cover
propagating water waves, authored waterfalls, ambient life, clouds/shadows, local
water mist, verified rock projection, guarded camera blur and reorganized settings.
Gameplay U39–U44 and the separate U45 removed-actor death-predicate correction
are committed. The supplied U45 autosave contains two living required creatures;
the original completion gates work when both die. `1b8b0f6` fixes a distinct
script-added looted-actor reload defect with 137 passing candidate checks.
The current qualified private export is `/home/llm2x/Documents/EI/local/scratchpad/menu-local-test-feedback-20261009/combined01`,
matching production checkpoint `e2e7e0af17d0a7cd7f7de20eea2e910e33038204`.
The latest original prison q71h/q72h route fix (`d13bac0`) passes
[630 checks](validation/prison-progression-late-join-2026-10-09.json); the earlier
discovery/alarm, renderer and native-binary evidence is inherited.

**Latest gameplay source:** `0cc6cdc` adds the original Gipat arrival effect for extra LiA co-op heroes, with [281 focused checks](validation/lia-zone7-arrival-2026-10-09.json). Its private `lia-zone7-movement-audit-20261009/candidate01` export changes only two gameplay scripts from `8195e68`, which preserves all eleven original prison damage/Sleep cycles for late and returning guests ([918 checks](validation/prison-damage-late-join-2026-10-09.json)). Arrival positions, original NPC movement, saved waits and quest behavior remain unchanged. The delivered Linux/Windows `.2` packages below remain at `e2e7e0a`; renderer lighting work is still separate and uncommitted.

**Updated Linux local test:** [`1.0.3-local.20261009.2`](/home/llm2x/Downloads/CursedLands-1.0.3-local.20261009.2-linux-x86_64.tar.gz), unpacked at `/home/llm2x/Documents/EI/local/builds/CursedLands-1.0.3-local.20261009.2-linux-x86_64`, uses checkpoint `e2e7e0a` and protocol 13. It fixes disappearing stone-menu labels after live graphics changes and the empty HUD before New Game loading, and includes the newly qualified prison route progression fix. All 262 compiled scripts and 673 resources match the combined export except its displayed version setting; only three production scripts differ from the prior discovery export. The actual package passes **73 checks** across live menu settings, base New Game, Continue and LiA New Game using the separate rendering thread. All loading runs show zero exposed HUD frames. Archive contents and executable permissions are verified. Isolated profiles preserve user settings and saves. The unfinished terrain-contact lighting experiment is excluded. [Package evidence](validation/linux-local-test-feedback-2026-10-09.json). The preceding [local test](validation/linux-local-test-2026-10-09.json) remains historical; neither package is a published stable release.

**Windows local test:** [`1.0.3-local.20261009.2`](/home/llm2x/Downloads/CursedLands-1.0.3-local.20261009.2-windows-x86_64.zip) is the Windows x86_64 counterpart of the updated Linux package, using the same `e2e7e0a` checkpoint and protocol 13. Its entire game pack is byte-identical (673 resources, 262 compiled scripts). The runtime was cross-built from Godot `5b4e0cb0f` with all ten committed desktop patches, and the native helper was rebuilt from the matching source. PE architecture, imports, native entry point, source provenance and full ZIP readback pass. **Windows execution remains untested**; this is a local test build. The later prison damage/Sleep and guest-arrival fixes and the unfinished terrain-contact lighting experiment are excluded. [Package evidence](validation/windows-local-test-2026-10-09.json).

[Previous junction evidence](validation/terrain-junctions-2026-10-09.json)
qualifies exact three/four-family Natural transitions across both campaigns,
with 19,911 GPU probes on three desktop backends and original-art controls.
The existing setting/default/presets remain unchanged. The Compatibility
neutral-field control retains the same one-pixel baseline residual; clean timing
and physical-device/long-route acceptance remain open. All 613 tracked game
files at that renderer checkpoint match candidate09; only two production scripts
and their regenerated UID files differ from its prior 712-file stage. Its
gameplay, settings, cloud and native-binary evidence is inherited.
[The V1 normal-frame follow-up](validation/ground-contact-side-loop-2026-10-09.json)
rejects a runtime two-triangle loop: 192 comparison checks and 12 exact RGB
pairs pass, but cold preparation shows no convincing reduction and steady
cost has an adverse signal. Foreign rendered processes overlap every timing
run. The two production edits were reverted exactly; the improved benchmark
separates synchronous setup, first draw, settling and steady viewport cost.
[Previous P1 retention evidence](validation/wound-source-retention-2026-10-09.json)
records 1,729 candidate checks and 15 captures, including 134 actual
GameUnit/Paperdoll/cloud/terrain lifecycle checks. It removes 6.875–7.125 MiB
of unused CPU source copies in a controlled appearance sample; all 39 uploaded
textures and mip chains remain exact. At that P1 checkpoint, all 613 committed
game files matched the tested stage; all 99 generated import/UID files matched
the preceding accepted stage.
[Previous texture integration](validation/renderer-texture-integration-2026-10-09.json)
records 190 runtime checks, 23 independent image comparisons and 37 captures for
the wound-only and compressed-terrain changes alongside existing cloud/effects.
At that checkpoint, all 712 post-import files matched its qualified wound-shader
candidate. The previous
[711-check/60-capture acceptance](validation/renderer-coop-integration-2026-10-09.json)
covers localized settings and representative co-op/solo return; gameplay source
and both native binaries are unchanged by subsequent renderer-only edits.
The earlier 859-check checkpoint and separate LiA mist motion limitation are
retained. The Haburu first-conversation fix is also committed. V7 requires
verified campaign placement data. Do not treat historical pause
statements in older evidence as a current stop instruction.

Subsequent gameplay checkpoints `fdf7885` and `82b749f` retain a renamed guest's
identity and carry aligned guest campaigns through scripted field transfers.
The shared-travel receipt records 152 passing checks, including actual ENet
transfers and separate solo loads. The user supplied saves for diagnosis and
explicitly wants the systemic sync issue fixed, without repairing the particular
latest save. `80c96d4` now preserves solo-earned character reimport and compatible
checkpoint selection (803 checks). `ec79e3f` protects stable hero references, and
`74c4804` restores pending scripted actions on solo return (149 acceptance checks
plus 36 formatting rechecks). `79bee8a` restores ordinary NEW-hero joins after
original opening initialization, with 239 passing base/LiA checks. The current
combined export includes all of these fixes. Whole-checkpoint compatibility
remains conservative about unknown authored flags.

The original worktree above is historical. Source version remains Experimental 6
and protocol 13. This task uses private exports and isolated profiles. Installed
builds, templates, original assets and real saves have not been replaced.
Current qualified private export:
`/home/llm2x/Documents/EI/local/scratchpad/prison-discovery-late-join-20261009/candidate01`.
The detailed gameplay tracker is `docs/gameplay-gaps-2026-10-08.md`; the incoming
handoff is `/home/llm2x/Documents/EI/local/gameplay-handoff-2026-10-09.md`.

P1 and P2 were selected in the audit's priority order because they can be
implemented in texture-loading/composition code without changing those gameplay
systems. The initial steps below are followed by the separately qualified P1
wound-only shader path and P2 terrain/scenery work. Other audit opportunities
and target-device acceptance remain distinct.

## Linux test feedback: menu labels and New Game loading — 9 October

`e2e7e0a` fixes all six menu labels disappearing when graphics settings refresh.
GroundContact had restored captured scenery materials after MenuScene installed
its labelled boards. It now tracks the material it owns, adopts eligible new
scenery bases and leaves unrelated replacements with their caller. Active
camera fades retain their underlying material and opacity. [Material evidence](validation/menu-material-refresh-2026-10-09.json)
records 112 passing checks, actual live option setters and viewed before/after
captures. The old build fails eight material-ownership checks and visibly loses
all labels. The screenshot's surrounding striped terrain was also isolated;
the optional clarification is unanswered and no terrain-style fix is claimed.

`eca50c0` prepares and presents the first-zone loading picture before awaiting
New Game's simulation worker. The old package showed 678 empty HUD frames;
both safe and forced-deferred candidate runs show zero (18 passing checks).
Failure paths release the loading picture. [Startup evidence](validation/menu-loading-start-2026-10-09.json)
distinguishes New Game from the previously tested Continue path. Final separate
render-thread package checks are in the package receipt above. The fixture
skips movie playback but uses the real menu, difficulty panel and worker.

## P1: retain outfit pixels for wounds

Historical first P1 step, superseded for shipped materials by the shader path
and source-retention removal below. `EIUnitModel._compose` retained the final,
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

## P1 follow-up: share native wound composition — 9 October

The first P1 step removed normal outfit readback. This follow-up also avoids
repeating native wound-layer composition for every outfit with the same mask,
human/creature limb layout and six damage levels. The complete GPU-overlay
proposal was evaluated first and was not shipped at this checkpoint for the
filtering reason below. The later shader checkpoint adopts an explicit different
filtering contract rather than claiming equality with the baked image.

### Accepted implementation

Only `game/src/game/unit_wounds.gd` changes production behavior in this checkpoint.
`_compose_layer` preserves the existing PNT3 byte compositor, ordered repeated
creature limbs, dimension checks and ARGB4444 truncation. It produces an immutable,
native-size image. `_build` still blends that image into a private copy of the
outfit and generates the same final mip chain. Resizing uses a private wound copy;
neither cached wound pixels nor retained outfit pixels are modified.

`_wounded` shares a completed layer or joins its in-flight producer. The first
request composes the wound and bakes its own outfit in one worker task. Other
outfits start their final blend after `_poll` observes that producer's completion;
workers never wait on another pool task. This can add a scheduling step for a
dependent outfit, so do not claim zero latency or rely only on blocking `flush()`
tests. The benchmark also exercises the ordinary frame poll. The synchronous
branch follows the same dependency/lifetime rules. Worker-written dictionary
slots are initialized before launch to avoid concurrent dictionary resizing.

The completed wound cache uses LRU order, capped at **64 entries and 4 MiB of
pixel payload**. Null entries count toward the entry limit. An oversized custom
layer can finish pending requests without being retained. This bound excludes
existing caches and in-flight/client-held image references. Eviction cannot
orphan a dependent job because it retains its producer's result. Shutdown waits
for active workers, drops deferred work and clears the added cache. Final
composite keys now include the human/creature layout as well as base identity.
The material's newest pending key still rejects stale health/outfit results.

Locations:

- [unit_wounds.gd:156](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/unit_wounds.gd:156): `_layer_key`, independent wound identity.
- [unit_wounds.gd:171](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/unit_wounds.gd:171): `_poll`, dependency publication and existing material ownership checks.
- [unit_wounds.gd:263](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/unit_wounds.gd:263): `_wounded`, request reuse/coalescing.
- [unit_wounds.gd:337](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/unit_wounds.gd:337): cache bounds; `_build` and `_compose_layer` follow.
- [wound_cache.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/wound_cache.gd): dependent jobs, source immutability, resizing, limb layouts, skips, healing, replacement outfits, world/preview/selection materials, eviction and shutdown.
- [wound_composition.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/benchmarks/wound_composition.gd): the same workload runs against frozen baseline/candidate packs; `--wound-render` adds real posed world and preview figures, selection, worsening and healing, with sharpening off/on.

The reference motivation remains R0 `Source/renderer.cpp:5436/5528`, with
base/wound admission at `Source/engine_bridge.cpp:6758`. This adaptation separates
CPU wound composition lifetime; it does **not** port their separate draw pass.

### Evidence and limits

The frozen application baseline is `fa0dd73`. Both sides use the same patched
Linux engine from the P5 cache checkpoint. Final candidate pack SHA-256:
`e0f0fd37d7c95eab2ba4305020efb2f9c2007b1cdc2267d84487c4d19d110f2d`.

- **1,211 candidate checks pass**, plus 846 baseline checks. The candidate total
  includes the existing 39-check retained-source regression, the 43-check cache
  fixture and the 201-check real-asset workload in both threaded and synchronous
  paths, plus 215 rendered checks on each of Compatibility, Forward+ and Mobile.
- All **48 composed texture outputs, including every mip byte**, match the
  frozen baseline in each of the five final composition runs. Cases use human
  `skin_00`/`skin_14`, real creature `unanwibo` wounds with duplicated limbs,
  and 64/128/256/512-pixel outfit variants. The resized variants are synthetic
  filtering/ownership fixtures, not a census of shipped outfit sizes.
- In each eight-outfit cold wave, native layer compositions fall **8→1**. With
  the layer cached, new outfits and albedo-cache eviction need **zero** new
  native compositions. Across all six waves the count falls 48→3. Final albedo
  blending, mip generation and **upload bytes remain unchanged**.
- All 24 Compatibility/Mobile render pairs are exact. Forward+ has at most
  **seven changed pixels at 1/255** in a 768×512 capture, including healthy/healed
  controls. A repeated baseline itself changes one pixel in two captures, but
  does not fully explain that residual. Do not call Forward+ pixel-identical.
- A QA-only Linux pack forces `Portability.threads()` false, and its reports
  confirm `threads: false`. It validates synchronous code, **not** an Android or
  browser build. Adding a `web` feature tag to a desktop template failed to
  select this path because the template still advertises `threads`; those
  earlier runs are explicitly superseded.
- Other game processes overlapped final runs. Timings remain diagnostic;
  no controlled frame-time, FPS or device-performance claim is made. Native work
  counts, byte comparisons and rendered captures are the accepted evidence.

The reproducible receipts, pack/engine/source hashes, output hashes, image
comparisons, rejected runs and read-only integration check are in
[wound-layer-cache-2026-10-09.json](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/docs/validation/wound-layer-cache-2026-10-09.json).
Full logs, exported packs and PNGs are under
`/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa/p1-wound-overlay`.
`final-suite.py` and `run.py` there replay the bounded, off-screen, no-focus
checks with isolated application data. A symlinked executable initially loaded
its target directory's old pack; final candidate executables are real copies,
and their pack hashes are recorded. No installed application or device was used.

### Wound-only GPU sampler experiment: keep as a diagnostic

[wound_layers.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/benchmarks/wound_layers.gd)
compares two real wound states on an atlas quad at 256/128/64/24 displayed pixels,
with sharpening off/on. Each run checks that independently reconstructed native
wound composition reproduces the current baked image. Its **six structural
checks do not mean the separate-sampler images match**. The report deliberately
measures those differences rather than accepting them as production quality.

The sampled human bases are **256×256**, while their wound layers are **128×128**.
Native-size independent sampling changes LOD/filtering. Resizing the wound to
base size before making its own mip chain improves large views, but still leaves
up to **37/255** channel differences in the distant mixed-wound case. The total
image error reaches about 9.7% of the wound signal on Compatibility and 20.9%
on Forward+ in this fixture; this ratio is diagnostic, not a perceptual score.
The visual comparison is saved as `sampling-comparison.png` in the QA directory.

The core issue is that filtering a pre-blended image generally differs from
blending independently filtered base and alpha values. Even opaque bases do not
remove this correlation. Color space also matters: Compatibility already works
in encoded space, whereas Vulkan `source_color` samples require the appropriate
conversion to approximate the remake's byte-color blend. The deliberately wrong
linear-blend control reaches 67/255 error on Forward+. Neither a naive second
sampler nor unconditional sRGB conversion is a qualified replacement.

The experiment established that GPU work must explicitly choose and validate its filtering/visual
contract, then preserve late-job ownership, detailed-head exclusions, soft-alpha
creatures and detached selection copies. If material state moves from the
albedo texture to new uniforms, `OrderMarks._bright_of` must synchronize those
uniforms too; at this checkpoint it resynchronized only albedo. This CPU cache
is the reusable first stage used by the later implementation below.

## P1 follow-up: shared wound-only shader textures — 9 October

Shipped `EIUnitModel.LitMaterial` and `PreviewMaterial` now retain their original
base textures and sample one shared native-size wound texture. Cold damage
states still compose the native PNT3/ARGB4444 wound bytes on a worker, generate
the wound's own mip chain and upload it. They no longer resize/blend that layer
into a replacement albedo for each outfit. A warm wound state reused by a new
outfit requires no additional wound job or upload. No graphics option was added.

### Sampling and ownership contract

The original reference uses a separate wound texture/pass; the prior remake
bake is documented as an approximation. This adaptation preserves the existing
base fetch, samples wound bytes as raw UNORM, applies encoded-colour straight
source-over RGB/texture alpha, and applies material opacity once. Each texture
keeps its own dimensions, LOD and sharpening. Native-size box mips are an
explicit remake antialiasing policy, not a claim about the original mip allocator.
Filtering before blending intentionally differs from the old baked result;
this is not complete native two-pass emulation or baked-pixel equivalence.

`UnitWounds._overlay` shares its native producer with any simultaneous legacy
job. The 64-entry/4 MiB CPU layer LRU also evicts its GPU mip texture; active
materials and pending jobs retain their own references. Weak pending consumers
check both current base identity and newest damage request. Healing clears the
binding immediately; changing an albedo cancels an old pending request. Actual
equipment/complexion changes rebuild models, and `OrderMarks` keeps active and
detached bright copies synchronized. Shutdown drains workers and drops caches.

Unsupported custom `StandardMaterial3D` keeps its existing per-albedo bake.
The existing collector supports instance material overrides and surface
overrides; it does not extend support to mesh-owned materials with no instance
override. All shipped unit figures use overrides. Detailed-head exclusions,
armour suppression, paired limbs and health thresholds are unchanged. At this
shader checkpoint, `SOURCE_IMAGE` CPU pixels still existed; its receipt does not
count their memory as eliminated. The following retention checkpoint removes
that now-unused owner from the shipped outfit producer.

### Evidence and limits

The [P1 shader receipt](validation/wound-gpu-2026-10-09.json) retains independent
native-byte and CPU sampling oracles, real human/boar/wisp world and preview
figures, sharpening, healing, selection, stale ownership, cache eviction and
custom fallback controls. Final Compatibility, Forward+ and Mobile runs each
pass 174 controls. Mobile uses HDR only for the strict numerical oracle; its
ordinary material/figure controls use the usual target. Ordinary Mobile
cross-program comparisons retain small dark-colour quantization differences,
so the HDR result is not presented as a passing 2/255 ordinary-target oracle.

The first production wrapper changed two healthy Forward+ silhouette pixels.
Keeping the original base-fetch statement in the fragment shader removes that
regression; saved pre-integration comparisons pass without widening tolerance.
Earlier filter/oracle setup failures, the Mobile precision control and the
failed comparisons remain in the receipt. Independent visual inspection found
no new fringe or silhouette damage in the accepted human, boar and wisp views.

For eight distinct 256×256 outfit identities sharing one authored human damage
state, cold output falls from eight replacement textures / **2,796,192 bytes**
to one native wound texture / **87,380 bytes**. Warm new outfits upload zero
additional wound bytes. These are bounded upload/allocation observations,
excluding outfit construction; they do not establish combat FPS or device
performance. The old baked appearance and independent sampling differ visibly
at some wound edges, as quantified in the receipt. Target-device and extended
gameplay acceptance remain separate.

## P1 follow-up: release unused outfit CPU source images — 9 October

The [retention receipt](validation/wound-source-retention-2026-10-09.json) closes
the remaining eager source-copy step for shipped figures. `EIUnitModel._compose`
now uploads the same composed image and mip chain without duplicating its base
pixels into `SOURCE_IMAGE` metadata. Shipped world, preview and selection
materials already use the wound-only shader and never consume those pixels.
No shader, sampling, native compositor, cache policy or graphics setting changes.

Custom `StandardMaterial3D` still uses the existing lazy base readback and cache;
an external texture producer can still supply immutable `SOURCE_IMAGE` metadata
to avoid that readback. The retained-source, absent-source and pending-publication
controls remain covered. A job retains its source across cache eviction; this
does not assert that its worker was still running at the exact eviction instant
or that fixture-held references had already been destroyed at shutdown.

The controlled corpus creates 16 distinct authored human appearances and eight
creature masks, then world/preview copies, selection, damage, healing, model
disposal, wound shutdown and equipment replacement. Its 38 distinct source
images previously retained **7,208,960 bytes (6.875 MiB)** after model disposal;
one redress increases this to 39 images / **7,471,104 bytes (7.125 MiB)**. Both
candidate checkpoints retain zero such images. This measures explicit metadata
ownership, not RSS, a whole-game census or the renderer's internal headless data.
The 39 uploaded base textures and their full mip chains remain byte-identical
(9,961,420 bytes), as do the real custom-material source and wound outputs.
Native wound layers and other asset caches remain outside this saving.

Focused headless and Compatibility tests confirm no readback or replacement
source cache on shipped wound requests, one readback per cached custom base,
zero readbacks with external metadata, immutable pixels and normal ownership.
The actual Forward+ GameUnit/Paperdoll lifecycle passes 134 checks with 15
captures while High clouds and Natural terrain are enabled, including actual
bright-material installation, healing, equipment replacement and retired owners.
Independent review confirms the unchanged upload/fallback bytes; world wound
and redressed Paperdoll images were inspected. Shader/settings/gameplay suites
are inherited where their source is unchanged, rather than counted again.

The candidate and previous combined export each contain 712 post-import files;
only `src/ei/unit_model.gd` and `src/game/unit_wounds.gd` differ. Both native
binaries match. All 613 Git-tracked game files match committed production
`0560069`; the remaining 69 `.import` files and 30 `.gd.uid` files match the
previous accepted stage. The source-comparison record and SHA-256 are appended
to the retention receipt. The existing tested export is qualified directly,
without rebuilding an identical pack. This is a private Linux checkpoint, without device/FPS claims,
publication, installation or changes to original assets or user saves.

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

## P2 follow-up: keep HD scenery output on the main GPU — 9 October

The first P2 step benefits textures used without HD upscaling. This follow-up
addresses the default HD scenery path. Previously `Gfx.texture_3d` upscaled on
a local RenderingDevice, read the enlarged image back, generated mipmaps on the
CPU, and uploaded the completed image to the renderer. The new path uploads the
original source once to the main device, runs the **same upscale shader**, builds
the mip chain there, and exposes the result as an owned `Texture2DRD`.

This is an adaptation of the P2 distinction between a texture ready for rendering
and a CPU-processing image, not a port of an upstream HD upscaler. Reference R0:
`Source/owned_asset_loader.cpp:1105/1297`,
`Source/renderer.cpp:2887` (`get_native_owned_texture`) and `Source/texture_mips.h`.
Their authored compressed-mip handling motivated the original P2 work; the HD
filter here remains the remake's existing Lanczos/de-ringing implementation.

### Implementation and ownership

- [tex_upscale_texture.gd:50](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/tex_upscale_texture.gd:50): `create` prepares a private RGBA8 source and creates resources on the rendering thread. The semaphore waits for CPU setup and texture dimensions, **not GPU completion**. The normal rendering graph orders compute writes before texture sampling; production does not submit/sync a local device or read the result back.
- [tex_upscale_texture.gd:7](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/tex_upscale_texture.gd:7): mip computation matches the pinned engine's encoded-byte `(a+b+c+d+2)>>2` average, including odd dimensions and one-pixel axes. UNORM storage and an sRGB-compatible shared view preserve the existing sampling semantics.
- [tex_upscale_texture.gd:25](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/tex_upscale_texture.gd:25): the wrapper owns its backing RD texture. Its last-reference notification detaches RenderingServer views and queues the backing release. A weak registry supports explicit shutdown without keeping ordinary cache entries alive. Temporary inputs, mip views and uniform sets are released after recording their commands.
- [tex_upscale.gd:138](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/tex_upscale.gd:138): `texture_2d` selects this path, with the existing `up2`/CPU-mip/ImageTexture fallback on unsupported backends or capability/pipeline decline. Null/empty sources return null. `shutdown` releases both resource types; `_shutdown_local` cannot invalidate resident scenery. Load-report milliseconds now explicitly describe foreground work, not completed GPU execution.
- [gfx.gd:1075](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/gfx.gd:1075): the HD scenery cache calls this factory; names, cache identity and missing-texture behavior stay the same. Terrain atlas callers still request CPU Images through `up2`. The HD-off compressed path is unchanged.
- [data_switch.gd:261](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/platform/data_switch.gd:261): include `_foliage` and `_foliage_local` in the existing data-source cache clear. A real-map test found three retained foliage material entries owning two resident textures; `EIFigure.clear_cache()` released them. Adding the two missing keys removes those references without changing scene loading or zone-transition ownership.

The resource teardown is necessary: `Texture2DRD` frees its RenderingServer
views, not the caller's backing RenderingDevice texture. An initial prototype
that called `release()` through the dying Resource leaked 14 backing textures;
the inline predelete cleanup passes last-reference and shutdown/restart tests.
Do not replace it with a wrapper that assumes Godot takes backing ownership.
The exact pinned engine files and hashes are recorded in the evidence below.

### Validation and actual scope of the saving

Frozen application baseline: `ca0ab88`. Both packs use the same patched Linux
engine from the prior P5 Mobile-lifetime checkpoint. Candidate pack SHA-256:
`c865b30128f1d790ece2e565c7638ec30df0f5899862008d42c710122752d21b`.

- **6,405 candidate checks pass**, plus 30 baseline scene checks. This includes
  394 texture/fallback/ownership checks, 66 candidate map checks and the existing
  5,945-check MMP regression across 628 assets.
- [hd_resident_texture.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/hd_resident_texture.gd) compares every byte of 14 output images and their complete mip chains on each of Forward+, Mobile and Forward+ with the production separate render thread: **42 exact outputs**. Fixtures cover wrapping/clamping, 1-pixel axes, odd and rectangular dimensions, opaque `govenorhouse00`, alpha foliage `tree02`, `rikarrowsmoke`, and restart. Additional checks exercise real `Gfx.texture_3d` caching, source immutability, last-reference ownership, local-device cleanup, forced resident decline, Compatibility and headless fallback. Headless checks do not claim rendered pixel validation.
- [hd_texture_scene.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/benchmarks/hd_texture_scene.gd) captures two frozen views of each of `bz2g`, `bz4g`, and `bz13h`, against both packs on all three rendering backends. **17/18 initial pairs are pixel-identical.** The remaining Mobile view differs at 127/480,000 pixels, at most 7/255; repeating the unchanged baseline reproduces that same image difference, while repeated baseline and candidate are exact. The candidate itself repeats exactly. A Mobile map on the separate render thread also matches its safe-thread capture exactly. All candidate cache clears leave zero resident textures and zero foliage material cache entries.

| Map | HD scenery textures | Final RGBA mip payload / avoided final upload |
|---|---:|---:|
| `bz2g` | 17 | 24,816,276 bytes (23.67 MiB) |
| `bz4g` | 10 | 16,078,152 bytes (15.33 MiB) |
| `bz13h` | 12 | 19,922,928 bytes (19.00 MiB) |

These are cold scenery-cache workloads, **not per-frame savings**. On the tested
Vulkan backends each texture also avoids its enlarged top-level readback and CPU
mip generation. The initial source upload and GPU filtering remain. Final GPU
texture payload, dimensions, draw counts and filtering are unchanged. This does
not compress HD output, reduce final VRAM, or eliminate terrain atlas readbacks.
Compatibility retains its existing CPU path. Other processes overlapped
the runs, and the new load timer excludes asynchronous GPU completion: do not
claim controlled load-time, FPS or device performance gains from these receipts.
Android, browsers, Windows and other GPU drivers were not tested in this batch.

### Baseline exit diagnostic and integration limits

The initial baseline map run rendered correctly but hung after the application's
`clean exit` trace; an initial candidate run did too. Matching-symbol inspection
placed the main thread in `WorkerThreadPool::exit_languages_threads` with only
one of four idle acknowledgements, empty queues, and sleeping workers. No engine
fix is included here. The final fixture explicitly shuts down the upscaler and
advances 24 normal frames while the renderer/pool still run; all final runs exit
normally. That makes the comparison reproducible but **does not establish that
the pre-existing production exit issue is fixed**. Failed/leaking prototypes,
the two timeout cases, the corrected fixture parse error, and the native traces
are retained rather than counted as successful validation.

The current checkpoint changes production only in `gfx.gd`, `tex_upscale.gd`,
the new `tex_upscale_texture.gd`, and the two data-source cache entries. No
character, controller, combat, network, or zone-transition implementation was
edited. The older `map_scene.gd` conflict was subsequently resolved in `f6c8922`;
this texture checkpoint added no new hook there. Fresh read-only applicability and target-preservation receipts,
commands, source/engine/pack hashes, test counts and image comparisons are in
[hd-resident-textures-2026-10-09.json](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/docs/validation/hd-resident-textures-2026-10-09.json).
The focused implementation/test patch passes against
`9e4576fcca1da0816e0002bb56290cbaedd3a60c`; the full accumulated implementation
reports only the known `map_scene.gd` conflict, and passes with that path excluded.
All 68 recorded implementation/test paths, target HEAD and status are unchanged.
The target's active controller and co-op delivery edits were left untouched.

## P2 follow-up: keep HD terrain arrays on the main GPU — 9 October

The terrain counterpart of `048a0cf` now keeps both original and gutter-padded
HD atlas arrays on the main RenderingDevice. It uses the same upscaling shader,
encoded-byte mip averaging, texture sizes, tile gutters and UVs as the previous
Image path. Water still samples the original atlas; detailed ground samples
the padded atlas. The HD option remains latched at map load, including lazy
detail construction.

Implementation locations:

- `game/src/game/tex_upscale_texture.gd`: `OwnedArray`, `can_try_array`,
  `create_array`, `_create` and `_free_inputs`. Input/output views select one
  layer and mip at a time, so the existing 2D compute shaders retain their
  pixel math. Uniform sets and transient views are released after recording;
  the wrapper owns the output backing RID and detaches server views before
  freeing it. Shutdown covers both 2D and array owners.
- `game/src/game/tex_upscale.gd`: `texture_array` supplies the established
  Image fallback when the main-device path declines.
- `game/src/ei/terrain.gd`: `_load_atlases` and `_ensure_detail_atlases` select
  the resident path only for eligible HD arrays. Compatibility, headless,
  HD-off and single-layer maps retain per-layer CPU processing. This avoids
  retaining all raw images in addition to their enlarged fallback outputs.
- `tools/tests/hd_resident_array.gd`: byte/mip equality, immutable sources,
  odd/one-pixel dimensions, wrap/clamp, missing magenta atlases, latched lazy
  detail, declined compute, last-owner release, shutdown and restart.
- `tools/benchmarks/terrain_atlas_census.gd`, `terrain_atlas_scene.gd` and
  `terrain_water_atlas_scene.gd`: map census, real rendered atlas use and a
  visible-water fixture. Test-only readbacks are not production reads.

The pinned engine's `scene/resources/texture_rd.cpp` **and**
`servers/rendering/renderer_rd/storage_rd/texture_storage.cpp` reject
single-layer RD arrays. Those custom maps use the original path rather than
allocating a fake second layer. All 38 base-map headers inspected have 3–8
layers. No additional engine patch is needed; the existing Mobile shader
lifetime/lock patch remains a prerequisite for this branch.

Evidence is in
[`validation/hd-resident-terrain-2026-10-09.json`](validation/hd-resident-terrain-2026-10-09.json).
The initial candidate passes 5,351 checks, with 143 baseline checks. All 96
real layer/mip comparisons (48 distinct outputs on each of Forward+/Mobile)
match every byte. There are 112 exact baseline/candidate render pairs across
three terrain maps, visible water on `zone1`, all three desktop renderers and
HD-off controls. Draw counts match in every pair. Initial buried-water focus
points are not treated as proof of visible water: the additional `zone1`
fixture verifies an actual water surface and a visible water-option response.

The final per-layer fallback correction passes another 901 checks, including
real Forward+ array bytes with a separate render thread, Compatibility and
headless lifetime/fallback cases. Its 32 production map captures match the
frozen baseline exactly, with unchanged draws. Evidence separates the initial
and final pack hashes. An early fixture held array references until function
return and failed its own release assertion; moving that readback loop into
a helper resolves the fixture issue, and the superseded run is excluded.

For the tested eight-layer maps, constructing both HD arrays avoids **82 MiB
of enlarged-image readback and 109.33 MiB of final image/mip upload**, as well
as CPU mip generation. Original source decoding, gutter preparation and source
GPU upload remain. The final RGBA8 GPU payload is unchanged. This is a cold
map-construction transfer saving, not a per-frame saving, measured peak-memory
reduction, FPS result or physical-device claim. Recorded foreground setup
times do not measure asynchronous GPU completion.

`TerrainColorCache` currently consumes array pixels only on Compatibility;
if it is enabled on Vulkan later, its layer readbacks must be accounted for.
The previously documented native worker-pool exit issue remains separate:
fixtures release upscaler resources and drain frames before quitting, and this
checkpoint does not fix the engine issue. The following HD-off follow-up now
handles compressed raw arrays; HD memory policy and Android/browser acceptance
remain separate work.

## P2 follow-up: preserve compressed raw terrain arrays — 9 October

With HD textures off, `_load_atlases` now uses the existing authored-mip MMP
decoder for original land/water arrays. Eligible opaque DXT1/DXT3 levels stay
compressed. This preserves the original authored levels instead of replacing
them with new averages of mip zero. The existing tiny-tail encoder, alpha
fallback, S3TC capability check and source-color sampling remain in force.
There is no new option or engine patch.

An array requires a uniform format. If any layer needs a different format
(for example transparency, a missing atlas or a large missing mip tail), the
loader decodes the other layers to RGBA without regenerating their authored
mips. Already generated BC1 tail blocks remain decoded from those blocks in
this mixed case. Both atlas loaders also reject incorrect heights as well as
widths and retain magenta placeholders. HD upscaling, lazy padded detail,
gutter extrusion and the per-layer CPU fallback remain on decoded pixels.
`TerrainColorCache` reads the padded array, which is unchanged.

The source is `game/src/ei/terrain.gd`. Focused fixtures are
`tools/tests/terrain_compressed.gd`, `terrain_compressed_upload.gd`,
`tools/benchmarks/terrain_compressed_scene.gd` and `terrain_array_memory.gd`.
Evidence, frozen source/build hashes and commands are in
[`validation/compressed-terrain-2026-10-09.json`](validation/compressed-terrain-2026-10-09.json).

The accepted Linux exported-runtime runs pass **20,845 candidate checks**;
baseline controls pass 16. They cover all **89 maps / 588 layers** in the two
installed campaigns, complete Vulkan layer/mip readback, explicit shader LODs
on all three desktop renderers, mixed/transparent/missing/single-layer cases,
latched detail, 501 existing HD guards and allocation release. The map census
finds 88 compressible maps. LiA `zonefinal001` has only four authored levels,
so its three-layer array takes the RGBA path. LiA `zone3dun1` has one complete
ten-level DXT1 layer and stays compressed. All authored payloads/pixels checked
in the Vulkan readbacks are exact.

Godot's GLES `texture_2d_layer_get` renders only mip zero and regenerates its
readback mips. The first test incorrectly treated those as the uploaded chain;
its failed output is retained. Corrected GLES checks use explicit shader LODs,
with independent authored RGBA pixels and CPU-decoded candidate tail blocks.
The existing 6/255 allowance for hardware BC decoding is unchanged; the raw
sampling maximum is **3/255**. No production change was needed for this test
oracle correction.

There are 96 accepted captures, including 32 complete-scene pairs against the
authored-RGBA control. Forward+/Compatibility `bz2g` differs by at most 3/255.
The RGBA final-map control has three far pixels at 1/255 due to its quantized
generated tails. Mobile `zone1` repeats exactly. Matching its generated tail
blocks removes two distant pixels that differ by up to 15/255; four close
dark-blue pixels remain at 7/255 after native BC decoding and the existing
spatial material/color pipeline. These small measured differences are retained
as limits, not reported as exact image equality. Padded detail without visible
water is exact; all reference-pair draw counts agree. Inspected near/far land,
lava and coastal-water images show no missing tiles, orientation changes or
new visible seams.

The sum of **per-map raw array payloads** is 45,266,984 bytes instead of
362,107,900 for base maps, and 61,171,276 instead of 459,974,900 for LiA. These
are not simultaneous residency or a deduplicated corpus. On the RTX 3090,
engine-reported raw allocation for eight-layer LiA `zone1` falls from
11,206,656 to 1,441,792 bytes on Vulkan and 11,184,800 to 1,398,208 on GLES.
Padded detail allocation is unchanged, and all measured arrays return to the
same allocation baseline after release.

This is a texture-memory result, not an FPS or general load-speed claim.
Preserving/scanning more authored data can add load work: the recorded Vulkan
final-map raw load was 1.8 ms before and 5.0 ms after. These single observations
do not isolate OS cache or the concurrently running headless gameplay route.
The HD payload remains RGBA8; other vendors, Android, Web and non-Linux targets
still need their own acceptance. The private test pack is not an installed or
published build. Independent source review found no actionable production or
lifecycle issue.

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
  and changes only that object's material during a fade. The `DialogCamera` obstruction check likewise reads individual visible
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
constraints above. Preserve gameplay visibility when testing P4; rendering experiments must not
change whether creatures exist or can be targeted.

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
start with measured hidden-geometry cost and preserve logical
visibility/guard behavior in the story/co-op scripts.

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

This first-stage checkpoint implemented the local-light selection policy;
P4 visibility changes were evaluated separately. The original
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

## P5 follow-up: validate native Mobile shadow fades

The native `mobile` renderer now uses the same bounded opacity transitions on
desktop. `--no-local-shadow-fades` retains the immediate switch for comparisons.
Constrained native Mobile stays off by default and accepts `--local-shadow-fades`;
the disable switch wins when both are present. Android/web still default to
Compatibility in `game/project.godot`. Forward+ and Compatibility retain their
previous policies, and the user's continuous-desktop/held-device sun policy
remains separate.

This adapts R0's 0.4-second transitions in `Source/point_shadow_policy.h:13`
and `PointShadowScheduler::select` around line 275 to another remake backend.
The reference's work budget must still not be interpreted as our resident-light
limit. Our four-total/two-lava caps and sequential outgoing/incoming fade legs
are preserved. No selection, light energy, map caching or custom shader math
changes were needed for this step.

### Source and implementation locations

- `game/src/game/fx/local_lighting.gd:53` contains the renderer/platform gate.
- `tools/tests/local_shadow_fades.gd:234` checks flag/opacity continuity and
  records the actual production gate; its rendered transition checks now run
  on Mobile too. The report includes the actual constrained-platform feature.
- `tools/tests/local_shadow_selection.gd:221` clears mouse confinement before
  making the diagnostic window unfocusable/minimized, avoiding X11's `NO GRAB`.
- Existing `tools/tests/local_light_passes.gd`,
  `tools/tests/local_shadow_importance.gd` and
  `tools/tests/material_shader_options.gd` cover the actual composed shaders,
  selected lights and option switches on this newly validated backend.
- In the pinned engine source at
  `/home/llm2x/Documents/EI/local/scratchpad/coop-performance-20261005/engine-profile/godot-5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88`,
  `servers/rendering/renderer_rd/storage_rd/light_storage.cpp:1160` supplies
  native shadow opacity. Mobile includes the shared implementation at
  `servers/rendering/renderer_rd/shaders/forward_mobile/scene_forward_mobile.glsl:1038`;
  `servers/rendering/renderer_rd/shaders/scene_forward_lights_inc.glsl:502`
  gates sampling and line 626 blends its result with full illumination.
  Mobile therefore does not need `LocalLightShader`'s GLES colour correction.

### Validation and limits

The final Linux export passes **7,209 checks**: desktop Mobile fades (924),
simulated constrained default (738) and opt-in (924), explicit disable (738),
both flags (738), 18 lighting-boundary cases (155), selection (425), importance
(358), 108 drawn shader variants (362), and Forward+/Compatibility fade
regressions (923/924). All 14 fade images match the earlier QA-only override
on the frozen `9478a97` export exactly.

The visible exchange changes 47,626 pixels. Its largest immediate RGB-channel
change is 33/255; eight sampled 0.1-second steps peak at 8–11/255, with an exact
settled endpoint. Partially faded shadows follow moving casters and lights.
All 18 candidate flag/zero-opacity boundary cases are exact in this run. Across
the baseline comparison, 34/36 lighting images are exact; two differ by at most
2/255. These small differences are retained in the evidence, not reported as
total pixel identity. All 36 Forward+/Compatibility regression images match
the preceding checkpoint exactly.

The constrained-policy runs use a separate Linux export copy with
`_custom_features="mobile"` in its adjacent `override.cfg`. The suite verifies
that `Portability.constrained()` and the native Mobile renderer are active.
This checks the real platform branch, not Android hardware or driver quality.
The first attempt used the wrong key `custom_features`, stayed unconstrained
and logged `NO GRAB`; it is excluded from acceptance. Most fixtures use a 2048
atlas; the separate small-atlas boundary case uses 1024. The report's
`light_limit` field is an OpenGL setting, not Mobile's eight-per-type receiver cap.

No FPS or GPU-cost benefit is claimed. There is no added custom colour-conversion
shader path, but opacity writes and native shadow rendering still cost work.
Some correctness runs overlapped unrelated Godot processes, recorded in the
evidence; those processes were untouched. Physical Android testing, full-map
and caster-aware selection acceptance, and static/dynamic map caching remain
open. The Retroid and installed builds were not modified.

Exact source/export hashes, commands, captures, platform-gate results,
discarded attempt and read-only integration check are in
[local-shadow-mobile-2026-10-08.json](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/docs/validation/local-shadow-mobile-2026-10-08.json).
Raw runs, the frozen candidate, baseline probe and sequential reproduction
suite are under
`/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa/p5-mobile/`.

## P5 follow-up: let stationary foliage reuse native shadow maps

Godot already retains complete local shadow maps. The disabled foliage wind
branch still referenced `TIME`, so Godot classified those materials as animated
and repeatedly dirtied overlapping lights even when their `wind` uniform was
zero. This checkpoint removes that inactive vertex branch at shader compilation
and gives authored rigid plants a permanently stationary shader. Wind settings,
light selection, shadow strength, sun policy and scene ownership stay as before.

This follows R0's principle of avoiding repeated static shadow work, not its
separate static-depth/dynamic-overlay implementation. See R0
`Source/renderer_point_shadows.cpp:28–88` (separate page allocation) and
`138–139` (static/overlay slots), at
`d529d14e9bf3c960833a9d9633786fc4588ec6d2`. Godot's whole-map reuse still stops
when a contributing caster, light, material or relevant atlas allocation changes.
Animated characters, wind-on foliage and particles can still require redraws.

### Implementation and engine prerequisite

- [figure.gd:30](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/ei/figure.gd:30): wind branch marker and permanent `FOLIAGE_STILL_SHADER`. `foliage_material_for` selects the appropriate shared program and passes that source to ground-contact variants.
- [figure.gd:589](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/ei/figure.gd:589): `set_wind` recomposes shared programs. The material's `wind` uniform now retains authored strength (1 for normal sway, 0 for rigid plants), rather than mirroring the global switch. Material copies made while wind is off therefore animate correctly when it is restored.
- [gfx.gd:203](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/game/gfx.gd:203), `compose` and `set_foliage_wind`: compile inactive deformation out, including contact variants; no new per-frame scan. Changing the option can incur shader preparation work.
- [camera_fade.gd:214](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/game/src/ui/camera_fade.gd:214): refresh cached dither programs in place after wind or other surface/fog recomposition. Active material/shader identities, textures, per-part values and fade strength survive. This does not change camera movement, visibility selection or fade ownership.
- [mobile-shader-recompile-lock.patch](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/engine_patches/godot-4.7/mobile-shader-recompile-lock.patch): **required for native Mobile acceptance**. Finish pending pipeline jobs before changing shader state or taking the compiler mutex, then confine that mutex to the compiler call. See the [template recipe](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/engine_patches/godot-4.7/README.md). Adding the patch does not update installed templates; Linux was built in a separate QA copy. Windows/Android/macOS builds still need validation. Compatibility and Forward+ engine code are unchanged.

Pinned engine: `5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88`, in
`/home/llm2x/Documents/EI/local/scratchpad/coop-performance-20261005/engine-profile/godot-5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88`.
Useful source locations:

- `servers/rendering/renderer_scene_cull.cpp:3607–3641`: dirty/version tracking, atlas update and re-dirtying for animated casters. `renderer_scene_cull.h:719–745` uses the normal rendered-frame counter for multiple-camera handling.
- `drivers/gles3/storage/material_storage.cpp:3215` and `servers/rendering/renderer_rd/forward_mobile/scene_shader_forward_mobile.cpp:252`: animation classification depends on vertex `TIME` use, not a runtime zero uniform.
- `servers/rendering/renderer_rd/storage_rd/light_storage.cpp:219` and `drivers/gles3/storage/light_storage.cpp:144`: energy/opacity changes do not increment the depth-map version; movement/range/bias changes can invalidate it.
- Unpatched `forward_mobile/scene_shader_forward_mobile.cpp:169, 242, 478`: the code setter held the singleton mutex while waiting for pipeline work whose variant lookup needed that same mutex. `renderer_rd/pipeline_hash_map_rd.h:87, 214` contains the wait/clear operation. The final patch moves that wait before version mutation as well as correcting lock scope.

### Rendered acceptance and limits

[local_shadow_cache.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/benchmarks/local_shadow_cache.gd)
loads actual maps and authored torch placement/radii through `ParticleFx`, then
selects shadows with the production manager. It freezes gameplay and simulation,
omits units/grass/directional shadows, and samples 48 normal rendered frames per
state. `force_draw()` is unsuitable for this cache test: it does not advance the
engine clock used by the dirty-shadow logic. Keep the off-screen window drawable;
minimizing it suppresses normal X11 draws. All runs use isolated data directories,
`--render-thread safe`, no focus and a bounded runner.

| Authored map / selected torch | Overlapping foliage meshes | Baseline wind-off shadow primitives/frame | Candidate wind-off shadow primitives/frame |
|---|---:|---:|---:|
| `zonemainmenunew`, radius 5 | 12 | 16,266 | 0 |
| `zone3obr`, radius 5 | 3 | 14,933 | 0 |

These counts concern the selected static diagnostic scene, not whole-game FPS.
Compatibility and Forward+ reproduce the result; the patched Mobile renderer
also reuses depth. Motion of the authored light or an authored fireplace mesh
resumes updates, restoring either returns to zero updates and the original
image, and wind restoration resumes animated shadows. Changing energy/opacity
alone keeps static depth cached. Sixteen paired Compatibility captures, including
settled motion endpoints and restorations, are byte-identical to `851a843`.
Eight additional Mobile comparisons are exact with both application revisions
on the final patched engine (24 paired captures total).

Counter caveat: use shadow **primitives**, not the GLES shadow draw counter.
Pinned GLES leaves that draw counter at zero and counts shadow submissions in
its `VISIBLE/DRAW_CALLS` field (`rasterizer_scene_gles3.cpp:3929`). The raw
`visible_draws` field therefore falls 129→74 and 217→190 here without a change
in visible scenery. Mobile's shadow draw field is assigned per pass rather than
summed (`render_forward_mobile.cpp:1600`). None of those fields should be
misrepresented as directly comparable color-pass draws across backends.

[foliage_shadow_cache.gd](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/tools/tests/foliage_shadow_cache.gd)
uses real foliage materials and exercises base/contact/dither combinations,
rigid plants, off→on→off→on changes, and unrelated material-option recompilation.
It requires exact stationary pixels, zero inactive depth updates, restored
animation/depth updates when enabled, retained textures/resources/fade values,
and identical off-state restoration. The existing foliage, ground-contact,
scenery-batch and material-option fixtures are also retained and extended for
the stationary shader. The final engine passes 141 focused checks on each
backend and 416 Mobile material-option checks (126 drawn shader variants).
The existing engine also passes 25 headless/28 rendered foliage checks, 35
ground-contact checks, 119 live scenery checks, 416 Compatibility material-option
checks and 141 legacy/dynamic-shader cache checks. Four candidate map runs pass
34 checks each; three paired baseline map runs pass 33 each. The acceptance
set contains 1,739 candidate checks and 99 baseline map checks. Exact per-run
commands, source hashes and earlier rejected/control runs are in the evidence.

The engine diagnosis is part of this checkpoint, not a silently ignored test
failure. The original export stalled on `zone3obr` after wind-on. A separately
built matched engine control, differing only in the Mobile code setter, also
stalled and was terminated at 60 seconds. Narrowing the mutex alone removed
the stall but caused 36 render-thread-only RID errors and leaked shader RIDs;
that binary is rejected. Waiting before shader-version mutation removes those
errors. The final settled run completes all map assertions without engine
errors or resource warnings.

Short startup captures are not accepted as steady-state comparisons. The small
Mobile fixture showed a 41-pixel change above 2/255 (peak 7/255) on its first
static sample, reproduced with identical before/after PNGs on baseline and
candidate. It now uses 120 initial warm-up frames. The map's early 16-frame
warm-up showed 11 differing pixels (peak 7/255) during shader preparation;
Mobile acceptance uses `--shadow-cache-warmup=240`, keeping strict image checks.
The exact internal source of that transient was not instrumented. The initial
map motion comparisons also used an ambiguous caster and unsettled endpoint;
final controls identify the same authored mesh and wait four frames after its
last movement. Superseded captures and rejected runs remain in QA.

Evidence: [local-shadow-cache-2026-10-08.json](/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008/docs/validation/local-shadow-cache-2026-10-08.json),
with raw logs, frozen exports, source/pack hashes and controls under
`/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa/p5-shadow-cache`.
Correctness runs overlapped unrelated Godot work; timing fields are diagnostic
only. No Android/browser hardware, installed build or real save was used. This
is a native-cache eligibility improvement, not the upstream split-depth cache,
a directional-shadow optimization or a demonstrated device/FPS speedup.

## P5 diagnostic: moving unit beside static local-shadow casters — 9 October

The separate static-depth/dynamic-overlay cache remains unimplemented. A bounded
Compatibility diagnostic now measures the actual work that a moving unit causes
beside the authored `zone3obr` camp fire. It uses an original Human Hero figure,
walk animation and walkable original navigation cells, one unchanged radius-five
light, a fixed 800×600 camera and the production light selector. The actor's
placement/pose is controlled; this is not a gameplay simulation benchmark.

The full/static-excluded ABBA sequence retains all visible meshes but deliberately
removes scenery shadows in the excluded arms. **44 checks pass**, with six
inspected captures: the body moves visibly, its own shadow remains, held shadow
primitive counts are zero, and restoring caster flags restores the exact image.
Every moving full arm submits 15,863 median shadow primitives versus 930 without
the static casters: 14,933 repeated primitives and 27 GLES draws. Colour-pass
geometry distributions remain unchanged across the four arms.

The two observed whole-viewport GPU differences are only **0.042 and 0.025 ms**;
CPU differences are **0.052 and 0.058 ms**. The 0.016 ms GPU drift between the
full arms is material. These are not isolated static-shadow costs: removing
static depth also changes dynamic-caster occlusion and the colour pass's shadow
values. No frame-rate improvement or cache performance is established.

A source-qualified Compatibility prototype could retain a static depth cube,
copy its six faces into the sampled cube and draw dynamic casters without
clearing it. This scene would add 786,432 depth-payload bytes and at least
1,572,864 theoretical read/write bytes per moving frame; copy latency is
unmeasured. Correct implementation also needs conservative caster eligibility,
separate invalidation versions, old/new bounds, full-light static coverage,
material/texture/LOD invalidation, bounded residency and complete owner/atlas
teardown. The [diagnostic receipt](validation/local-shadow-overlay-opportunity-2026-10-09.json)
records the pinned engine/reference source map and limits.

The small, noisy viewport difference does not justify that engine work for this
workload. Keep the fixture and investigate an expensive target-device workload
before implementation. No production switch, engine change or longer timing
matrix was added. The run has no other Godot process at either endpoint.

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
`p6-export.log` and the isolated `p6-export/` release. No installed build was changed.

### P6 normal-frame stability and redraw control — 9 October

The [normal-frame diagnostic](validation/directional-shadow-stability-2026-10-09.json)
uses the current qualified `texture-coop-final-01` pack on one original `bz13h`
fortress/palm view. Forward+ runs at 800×600 on RTX 3090 with the actual desktop
continuous aiming policy, Medium 4096 D16 shadows, fitted four cascades and
production bias/filter settings. Wind, units, optional effects and simulation
are held. This is separate from the older artificial-angle/forced-draw probe.

The clean run passes 162 fixture checks and saves 127 images without errors or
warnings. Stationary camera/clock images are exact, and returning all inputs
after the pan/clock traces restores the initial image exactly. Four held ABBA
blocks each sample 240 ordinary rendered frames after warmup. Shadow-enabled
frames repeatedly submit 73,589 shadow primitives and 776 draws; shadow-off
frames submit none. Both enabled/disabled viewport GPU median differences are
0.119 ms (0.264 versus 0.145 ms), and both CPU differences are 0.210 ms. These
are whole-viewport differences, not isolated depth cost or achievable cache
savings; no depth-copy, invalidation or cache-maintenance costs were simulated.

The short logical traces replay a 0.3 m/s camera pan and two seconds of authored
clock advance through the real aiming path, with shadow-off controls. Pan image
changes are mostly ordinary texture/raster motion. Clock-on changes show small
moving shadow edges; the clock-off endpoint stays within 2/255, with no pixels
exceeding that threshold, rather than being byte-identical. Inspected original frames
and exact-pixel edge crops show no demonstrated wrong state or basis jump; raw
temporal pixel counts alone do not establish objectionable shimmer. Fixed
PCF disk rotation with TAA off is not a random stationary jitter policy.

An earlier run logged a fixture-only pre-tree global-transform error while
reparenting the dummy Game's sun. Explicitly retaining its local transform
before the complete aiming assignment fixes setup; all 127 images match the
clean rerun byte-for-byte. The first run remains excluded from acceptance.

No production setting, sun policy or native renderer changed. Godot already
snaps cascade bounds; this stable held view and its modest measured cost do not
justify a larger projection/cache adaptation. Low sun, zoom, moving casters,
cascade crossings, long routes and actual target devices remain separate P6
acceptance work. No Windows/Android/browser or FPS result is implied.

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
variation matters, and one earlier exploratory run overlapped another
GPU process. The exported validation records other game processes at each start.

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

### V1 normal-frame preparation follow-up — 9 October

The remaining fixed two-triangle loop was tested with a private runtime bound
of two, leaving all eighteen candidate triangles, their order, highest-surface
selection, deformation and UV/Jacobian calculations unchanged. Only full
contact queries received the new parameter; cover/mound sources stayed exact.
The experiment is **rejected and reverted**, not a new production checkpoint.

`tools/benchmarks/ground_contact_cost.gd` now measures normal frames with
explicitly held graphics settings, 96 warmup frames and 240 steady samples in
off/on/repeated-on/restored order. It separately records synchronous material/
surface refresh and the first rendered frame. Its Python wrapper freezes the
fixture, isolates Godot/NVIDIA caches, verifies the cold-to-warm cache handoff,
samples foreign engine processes throughout and rejects capture mismatches.
The historical forced-draw benchmark remains available unchanged.

In the held 800×600 `bz2g` Compatibility view, cold near-contact refresh was
55.7/56.7 ms for baseline/candidate; first drawing was 14,336.8/14,101.6 ms.
Warm near GPU medians were 1.617/1.619 ms for baseline and 1.825/1.745 ms for
candidate; far medians were 0.564/0.564 versus 0.586/0.586 ms. Every run observed
foreign rendered processes, so these are diagnostic signals rather than a
clean causal performance comparison. They do not justify retaining the change.

All **192 comparison checks pass**, with **12 exact RGB baseline/candidate
pairs**, 24 captures and exact cold/warm PNG sets. A separate initial functional
baseline adds 48 passing checks; one earlier fixture parse failure is excluded.
The candidate differed from the 712-file qualified stage in exactly the two
experimental scripts. Both now match the qualified source again. No broader
renderer/device rerun was made for this rejected change. Do not repeat this
loop experiment, the earlier five/six-colour loops or already-existing
disabled-deformation specialization without a new basis.

[ground-contact-side-loop-2026-10-09.json](validation/ground-contact-side-loop-2026-10-09.json)
retains source/build hashes, frozen reports, process observations and exact
image comparisons. V1 preparation, broader lighting and route/device acceptance
remain open; defaults stay off.

### V1 lighting prototype and corrected oracle — 9 October

The private `ground-contact-relief-20261009/full-surface` prototypes extend the
painted-normal candidate with the terrain's actual procedural normal texture,
rain material profile and copied-ground highlight. The later `tracks` prototype
also reconstructs the installed triangle's interpolated, pre-displacement
compression and native aged footprint normals. Original material mode retains
its vertex lighting while using terrain fragment normals for rain and tracks.
Only the contact shader and shared `detail_nm` binding differ from the frozen
`e2e7e0a` game stage. **These are not promoted or shipped changes.**

The old normal oracle passed interpolated `wpos` to the contact sampler; actual
production uses `(INV_VIEW_MATRIX * vec4(VERTEX, 1)).xyz`. The latter clears all
three old ordinary/soft residual pixels without changing production code. One
different soft perspective error remains at `(139,121)`, with component error
`0.00218877` against the unchanged `0.002` threshold. A camera-relative derivative
variant leaves those actual-input captures exact and improves only three of
109 perspective failures at a synthetic +4096 offset. It is deferred, not a
qualified precision fix. Earlier stress receipts remain retained.

The expanded prototype passes **247 ordinary normal/profile checks**, including
both material modes and above/below, perspective, rotated and constant-art
controls. Seven unchanged native normal captures are byte-identical to the
preceding prototype. The actual authored `bz13h` house passes **63 checks**:
rain highlights affect 13,791 band pixels (10,324 by more than two bytes), a
controlled roof mask suppresses them exactly, and upper/outside/silhouette,
held and restoration controls stay exact. All 21 scene captures also remain
byte-identical after the separate footprint implementation. The roof textures
are explicit diagnostic controls, not a natural roof-placement validation.

With real installed snow footprints, strict errors fall from 3,379 to 93 in the
ordinary view, 2,494 to 82 after rotation, 3,445 to 46 in perspective and 2,488
to 67 below. The final run is **1,659 checks with eight retained strict normal
failures**, not complete parity. Original-material and detail-off controls also
retain track-edge errors. The native fragment-only ablation independently
affects 3,135 pixels. The first run additionally used a grass-specific >1000
procedural-response assertion on snow: snow has 292 affected pixels. The final
fixture retains the grass requirement, requires nonzero snow response and
keeps the normal tolerance unchanged. Native raster holes are excluded from
wet-response counts.

A bounded readback diagnosis explains the sampled footprint-edge residuals:
one-to-two-ULP coordinate differences cross measured bilinear filter coefficient
boundaries. Compression and pre-track normals agree closely, while independently
fitted coefficients reconstruct the differing track taps and final normals.
The measured model matches all 520 captured channels within `2.67e-8` on this
Forward+/RTX 3090 run. This neither establishes a universal hardware model nor
justifies snapping coordinates or relaxing the strict comparison.

The unchanged snow-covered `zone11` barrack, `Barrack00-6` / NID 1651, passes
**112 checks** with five controlled native footprint stamps at its wall root.
Isolating copied-ground track normals changes 1,746/1,389/1,455 contact-band
pixels by more than two bytes under sunlight/native point/local light,
respectively. Every outside-band pixel and restoration control remains exact.
Original meshes and placement are preserved. These are controlled stamps,
not a physical walking route or proof of complete terrain/object light parity.

The read-only lighting review confirms the triplanar axes, height-plane signs,
sampler binding, cloud/fog composition and mono view-vector convention. Nearby
point highlights remain approximate: their copied view ray is evaluated at
ground, but light direction/attenuation and shadows still describe the object
fragment. Shoreline vertex emissive/underwater terms, physical walking trails,
broader composition/backends, startup/steady cost and device
acceptance remain open. Foreign rendered processes were observed; no timing
claim is made. Settings and both delivered `.2` packages remain unchanged.

[ground-contact-lighting-prototype-2026-10-09.json](validation/ground-contact-lighting-prototype-2026-10-09.json)
records the frozen sources, builds, failed and passing runs, image checks and
precision diagnoses. The following shoreline stage continues from this
`full-surface/tracks` prototype; the dirty canonical shader is still the older
painted-only experiment.

### V1 desktop backend controls — 9 October

The unchanged tracks prototype passes **422 Compatibility checks**: 247 ordinary
normal/rain, 63 authored wet-house and 112 snow-barrack checks. Mobile passes
the same 247 ordinary checks but retains **12 scene failures**, five on the
house and seven on the barrack. Every shader path compiles; Compatibility's
unsupported screen-space-AA warning is the only engine warning in these runs.

One subsequent native **contact-Off** Mobile control has 108 checks and five
retained fixed-state failures. Its 212-pixel packed-light terrain drift exactly
reproduces the earlier held-frame differences, including signed RGB deltas.
Its sun settling also reproduces all 3,608 earlier object differences outside
the blend band, with inverse signed changes. Those patterns therefore occur
without contact executing. The original 12 failures remain failed; this does
not establish every Mobile scene difference's cause. Identical-code native
shader replacement/restoration becomes exact after settling. Compilation
submission counters do not prove completion or which pipeline rendered a frame.

[Backend evidence](validation/ground-contact-lighting-backends-2026-10-09.json)
retains all six runs, the CPU image analysis and that single native control.
No thresholds, settings, production files or packages changed. Feature
composition, full light/shadow equivalence, devices and cost remain open.

### V1 shoreline vertex-light prototype — 9 October

The private `ground-contact-relief-20261009/full-surface/shoreline/candidate02`
adds the native land vertices' baked emissive and underwater-lighting values
(`COLOR` E/k). It copies the retained original sector arrays into a lazy RGBA8
atlas with separate border vertices per sector. This preserves the original
first-liquid-material choice and byte packing; a fragment's water-cell material
can be different. Scripted water-height changes do not rebuild native baked
COLOR, so the prototype preserves that behavior. Original mode evaluates and
packs light at each selected vertex before interpolation; enhanced mode uses
interpolated E/k. The remaining native-light fallback also receives these terms;
the optional local-light addition keeps its original policy.

The data test passes **81 checks**, comparing all **147,456** actual packed
vertex colors on `zone1` and `bz13h`, plus lazy ownership and water-offset
controls. Same-pixel shoreline lighting has **65 checks with two retained
failures**. Original sun/point mismatches fall from 5,596/6,375 to zero;
enhanced mismatches fall from 5,698/6,595 to 230/217. Input comparisons pass at
the unchanged `1e-5` threshold. Restoring the native point-contribution helper's
structure clears two additional strict controlled-emissive pixels; all four
helper comparisons then pass at `1e-7`. No compiler-level cause is claimed.
Twelve native-light/input/ablation images remain byte-identical across packs.

The original `zone1` OrcBridge NID 1982 passes **72 scene checks** in Original
material mode. Removing only the copied E/k input changes 229 sun and 18 packed
point band pixels by more than two bytes. All outside/upper/silhouette, held
and restoration controls are exact. Enhanced mode retains **one of 72 failed
checks**: the packed-point effect changes 563 pixels by at most two bytes,
below the unchanged visibility requirement. Its containment/restoration controls
pass. The bridge root is dry with nonzero k and zero E; it is not a literal
liquid-plane crossing. A fixture correction uses original indexed vertices:
Godot's convenience `get_faces()` snaps its collision triangles to 0.0001 m.
The earlier edge-check and shader-fixture failures remain in the receipt.

Dense-color arithmetic remains a separate limit. The GPU expression matches
all **765 vertices from five real shoreline alpha triples** and its independent
readback control is exact. Seven synthetic emissive triples expose **169 of
1,071 synthetic vertices** with one-byte RGB differences (185 channels); all 1,836 alpha
channels match. This **113-check/one-failure** numeric fixture does not establish
physical footprint or full-scene parity. A proposed final-multiply correction
does not explain these cases: the native prepack values already pack correctly,
so an earlier arithmetic difference remains necessary.

[Shoreline evidence](validation/ground-contact-shoreline-prototype-2026-10-09.json)
records the two changed scratch production files, frozen builds, native source
audit and all passing/failed controls. The latest source is the shoreline
scratch stage, not the older dirty canonical shader. Enhanced precision,
synthetic emissive interpolation, composed/backend and device/cost acceptance
remain open. Neither delivered `.2` package contains these prototypes.

### V1 native mesh normals — 9–10 October

The next scratch stage, `full-surface/shoreline/precision/candidate01`, fixes a
source mismatch in the reconstructed normals. ArrayMesh packs ordinary normals
as two octahedral uint16 values; the contact atlas previously used uncompressed
`terrain.land_n`. The candidate reproduces the native packing and CPU decode
from retained sector arrays, preserving each sector's border ownership without
GPU readback. All **147,456** checked mesh NORMAL and COLOR entries match exactly
on `zone1`/`bz13h`; the data/lifecycle fixture passes **85 checks**.

The existing **247 ordinary normal/rain checks** and **72 Original-mode authored
bridge checks** pass. Enhanced shoreline light improves from 230/217 mismatching
sun/point pixels to **19/16**, retaining both strict failures in the 65-check
light comparison. All twelve native-light/input/ablation images remain exact.
The remaining differences are not hidden by new tolerances. Dense terrain also
re-packs its interpolated normals; that second packing stage remains separate.
[Normal evidence](validation/ground-contact-native-normals-2026-10-10.json)
retains the failed owner-lifetime diagnostic and wrong-argument bridge attempt
as invalid fixtures, alongside their corrected runs.

Re-reading pinned R1 clarified the acceptance scope: its contact receiver copies
the object and changes the normal/material, retaining the object's world/shadow
position (`native_shader.h:1639–1643`). It blends completed material colours and
reuses object sun/cloud visibility. A proposed independent folded-ground light
and shadow context would be a larger renderer extension, not a V1 requirement.
The reconstruction diagnostics remain useful for the chosen Godot adaptation;
they do not imply that R1 copies a complete terrain lighting response at another
position. The [pinned R1 scope correction](validation/ground-contact-r1-scope-2026-10-10.json)
retains the earlier backend audit as optional-extension evidence. The bounded
figure-versus-ground directional shadow transfer is being qualified separately.
Canonical production and both delivered packages are unchanged.

## Integration

### Completed combined checkpoint — 9 October

The renderer branch through `7202b8e` was
reconciled with the latest gameplay branch at
`09ffbf7cc6e820907ad80040cc232bd3665f4060`, including its unpublished fixes and
**protocol 13**. The one conflict in `game/src/ei/map_scene.gd` preserves
`CatacombLift.apply` before object placement and saved-position migration,
alongside the scenery manager and ground-contact attachment. Automatic merges
in `game_data.gd` and `game.gd` retain both the control options and sun policy.
The combined source was committed as `f6c89228b774eda8e8ea03724da53a71af9a09a4`
and the canonical checkout was advanced to it at
`/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo`.
Installed builds and published releases are separate from this source merge.

The exported combined Linux build passes **577 checks** across wound caching,
held-sun override, scenery/contact lifecycle, Mobile array ownership, five-rider
catacomb travel and old-save migration with batching enabled, and prison
late-join/real-ENet regression tests. The sun fixture's 10 desktop Compatibility
assertions also pass, but its immediate shutdown reports two texture leaks on
both the frozen pre-merge and combined build. An eight-frame drain did not
remove them; that test edit was reverted. Those runs are recorded separately,
not counted as clean passes or treated as a new merge regression.
See [`validation/renderer-gameplay-integration-2026-10-09.json`](validation/renderer-gameplay-integration-2026-10-09.json)
for source/runtime hashes, exact commands and the baseline issue.

Keep the Mobile engine patch when building new templates. Scenery batching and
ground contact remain opt-in/off by default. Desktop sunlight remains continuous,
including Compatibility; held sunlight is the constrained-device fallback and
explicit override. This merge does not establish a faster Android/web replacement.

### Historical applicability evidence

The checks against `40ea5a9`, `a8eb6ff` and `9e4576f` predate the completed
`f6c8922` integration. They left their target source, HEAD and status untouched,
with hashes retained in the P1/P2/P3 receipts. The former `map_scene.gd` conflict
is resolved: preserve `CatacombLift.apply`, saved-position migration, the scenery
manager and ground-contact lifetime together. No outstanding integration or
separate-owner approval is implied by those older records.

## C1: rigid character batching experiment — 9 October

The independently authored prototype is now in
`tools/benchmarks/rigid_part_batch.gd` and `rigid_characters.gd`. It is a
diagnostic only: no production character code, option or default changed.
The reference is R0 `Source/retained_static_submission.cpp`, especially
`merge_part_eligible`, `merge_parts_compatible` and
`retained_visual_merged_groups` around lines 2250–2273. That implementation
preserves a pose identity for each merged component; it does not establish
smooth skinning as an upstream feature.

Each source vertex follows exactly one original part. Original `EIAnimPart`
nodes and interpolation-before-parent-composition remain. Compatible material,
layer and shadow groups become skinned surfaces with flat, identity-rest bones.
Heads, weapons, morphs and the translucent wisp remain separate. The helper
updates the palette once after the original pose pass, avoiding the optional
`_weld` path's per-attachment override/forced skeleton updates. Original normals,
tangents and UVs are retained. Logical part metadata remains available to
geometry/particle consumers, but that alone does not cover gameplay integration.

The [validation receipt](validation/rigid-character-batching-2026-10-09.json)
records the frozen integrated PCK, patched engine/native hashes, commands,
source snapshots, screenshots and rejected fixture attempts. Twelve successful
diagnostic runs contain **1,046 assertions**. These check geometry, merge/bypass
policy and timing configuration; **they do not assert visual acceptance**.
Eight real figures, two views/pose phases and available idle/walk/attack/death
clips produce 60 broad comparison pairs per backend. The second state includes
rotation, detailed-head switching and native wound application. Dragon/wisp
have no resolved authored walk clip in this sample; those four views are
explicitly skipped. All 180 independent-original control pairs are exact.

Human body submission drops from 14 meshes to one surface, or 17→4 total visible
draws on Compatibility/Mobile and 34→8 on Forward+. Merged vertex positions
remain within 2.2 micrometres of the reference in the sampled figures. Sparse
image residuals remain: at most 9/12/13 pixels above 2/255 on
Compatibility/Forward+/Mobile. Their exact cause is unresolved; proximity to
image edges is not proof of a rasterization cause.

Two correctness problems prevent runtime adoption:

- **Light selection changes.** With twelve nearby point lights, Compatibility
  changes up to 14,738 pixels above 2/255, versus at most one with four lights.
  The torso/leg shading difference is visible. The pinned engine's
  `renderer_scene_cull.cpp` around line 3049 ranks lights using each mesh centre,
  energy and range. A whole-body bound cannot assume the old parts' light sets.
  The P3 complete-light guard is useful precedent, but repeatedly regrouping
  animated bodies would itself need a cost and lifetime evaluation.
- **Picking changes.** `GameUnit.screen_rects` and `MeshScreenRect.of_context`
  currently return one rectangle per drawn mesh. `Game._pick_unit` prioritizes
  these over loose union hits. The exact production query confirms that a
  merged body promotes gaps between limbs to precise hits; up to 41,902 pixels
  change classification in the 512² human fixture. Retain logical part
  rectangles independently of render batching before changing this path.

Uncapped desktop measurements use 32 walking human figures, normal rendered
frames and an original/merged/merged/original sequence, with 160 measured
samples per case after warmup. Linux RTX 3090 results:

| Renderer | Original frame median, ms | Merged frame median, ms | Visible draws |
| --- | --- | --- | --- |
| Compatibility | 1.637–1.641 | 1.687–1.707 | 544→128 |
| Forward+ | 1.452–1.483 | 1.539–1.582 | 1,088→256 |
| Mobile (desktop Vulkan) | 1.358–1.371 | 1.471–1.521 | 544→128 |

Palette synchronization adds 0.257–0.268 ms. Saved submission work does not
offset it in this fixture; Compatibility GPU time also increases. These are
isolated character-rendering measurements, without AI/network/full maps or
shadows, not gameplay FPS or Android results. No other Godot render process was
seen at run boundaries; clocks/background load were not locked. A later frozen-camera check explicitly disables inherited physics interpolation
so CPU picking queries use the rendered camera transform; all 120 repeated
Compatibility image hashes match and the picking verdict is unchanged. The earlier
8.33 ms timing was capped by delayed saved window settings and is rejected.
The final fixture sets both options and engine state and asserts an uncapped
configuration. First-build asset warmup makes construction totals incomparable.

**Decision:** retain the experiment; do not enable it in gameplay. A useful next
attempt must first remove redundant pose/palette work, preserve per-part picking
and light selection, and share immutable merged geometry. It must then cover
part visibility/severing (shrinking a bone to 0.001 is not full removal), gear
and material replacement, selection highlights, deferred/hidden poses, shadows,
portraits, particle attachments, limb copies and lifecycle cleanup. The current
helper's `weld_mesh` metadata is preparation, not proof of those contracts.
Enabling `smooth_joints` remains unrelated and would change authored shapes.

### V4 source preflight for the next implementation

No water code changed in the C1 checkpoint. The next visual task remains
bounded unit contact/wakes in the existing water pass. Source inspection found:

- R1 `Source/engine_bridge.cpp:24288`, `build_liquid_ripples`, rejects invisible,
  dead and undetected units, emissive liquids, dry/buried water and figures whose
  posed bounds do not actually reach the surface. Do not infer contact solely
  from a unit's navigation position or flying class.
- R1 `renderer_liquid.cpp:62/141/190` owns fixed game-time wave steps, bounded
  unit inputs, motion/presence easing and GPU-buffer lifetime. Contact/wake
  shading is in `shaders/liquid_surface.hlsl:386/420`. The 512² compute field is
  a reference design, not a requirement for our Compatibility/web path.
- Our `EITerrain.WATER_FX_SHADER` already combines original water colour with
  procedural/rain slopes, reflections, glints and shore foam. Contact slopes
  must affect both the reflected ray and glint normal; a separate overlay can
  conflict with the established unit→water→particle draw order. Preserve the
  original-water shader and lava/swamp branches.
- `EITerrain.water_at` is a cell lookup using the maximum of two authored
  corners, not the rendered triangle height. `Water_x_y` meshes retain the
  actual vertices and material indices; waves and `SetWaterLevel` offsets move
  them in the shader. Contact admission needs to account for this distinction,
  especially beside sloping water, bridges and flooding. Do not reuse the cell
  lookup as an exact visual-surface oracle.
- `GameWorld.visible_units` supplies an existing visible roster, and units have
  presented transforms for co-op smoothing. `UnitFog` must run before a visual
  contact is admitted; hidden units must not reveal themselves through wakes.
  `GroundMarks` already owns step events but does not implement unit-water wakes.
- `Game` processes while paused. A new child effect needs an explicit pause,
  loading/zone-hold and lifecycle policy. `GameWorld.draw_time` follows the
  authority logic accumulator; remote client effects have a separate clock.
  Do not use snapshot time or shader `TIME` as a universal game-time source.

Start with an independently authored, bounded contact implementation and
controlled standing/moving/turning/entry/exit views. Validate pause, 2× time,
hidden/flying/bridge units, water-level changes and option/world teardown before
rollout. Caustics, the wave-equation field and waterfall shells remain separate
parts of V4; no part of that additional behavior is implemented by C1.

## V4: optional water contacts and wakes — 9 October

Implemented the first bounded contact/wake adaptation in the canonical checkout.
The new **Water contact and wakes** option (`gfx_water_interaction`, Remake
group 15, row 7) defaults **off on every platform**, requires Water and lava
effects, and is also disabled by the lower automatic graphics tiers. Nothing
was installed or published. Desktop continuous sunlight and the Android/web
held fallback remain unchanged.

### Reference and implementation map

The design follows R1 `Source/engine_bridge.cpp:24288` (`build_liquid_ripples`),
`Source/renderer_liquid.cpp:62/141/190` (game-time stepping and motion/presence
easing), and `Source/shaders/liquid_surface.hlsl:386/420` (contacts and wakes).
This Godot implementation is independently authored. It does not port the
512² compute field or add a new transparent overlay.

- `game/src/game/fx/water_surface.gd`: lazy visual-surface query over the actual
  `Water_x_y` mesh triangles. Reuses `EIWaterWaves` and authored material/phase
  data, applies `SetWaterLevel` before wave displacement, and selects the highest
  containing deformed triangle. The coarse `water_at` grid is only a broad phase.
  Two-metre buckets and cached deformed vertices bound repeated query work;
  a 16-sector LRU owns CPU arrays with weak mesh/node identities. Replacement
  and removal invalidate the entry. Clearing the option/world releases it.
- `game/src/game/fx/water_interaction.gd`: a `Game` child with explicit pausable
  processing and priority 3, after visible unit presentation/fog. The existing
  visible roster supplies candidates. Up to 32 nearby candidates are queried
  to fill 16 contact slots within 55 m of the camera. Actual posed mesh bounds
  must cross the surface; script-hidden, fogged, dead, fully submerged and
  hovering models are rejected. Lava/swamp are excluded. Entries hold weak
  unit references, ease presence/motion/direction, fade at their last position
  after leaving water, and reset instead of drawing across teleports.
- The controller uses scaled process delta, not authority `draw_time` or shader
  `TIME`. Tree pause, loading, zone holds, movies, disabled travel-map worlds
  and unregistered LMP worlds hold the history. Remote presentation has its own
  visual clock. World changes, removed units and option disable clear state.
- `game/src/game/fx/water_interaction_shader.gd`: bounded contact rim/foam and
  divergent wake slopes in the existing water program. Their normals feed the
  existing reflection/glint path. Slopes and foam fade with camera distance;
  the existing depth/shore/lava/swamp handling remains. No added water draw,
  vertex displacement, targetable actor, navigation state, save field or packet.
- `game/src/ei/terrain.gd:1025`, `apply_gfx`, lazily creates a separate opt-in
  shader and restores the original program on disable. `set_rain_cover` also
  binds the current roof texture to this variant. `game/src/game/game.gd`
  constructs the controller; `game_data.gd`, `remake_text.gd` and `gfx_detect.gd`
  supply the option, translations, apply hook and conservative tier policy.

### Evidence and limits

The complete commands, source/pack/runtime hashes, results, rejected trials and
process-boundary observations are in
[water-contacts-2026-10-09.json](validation/water-contacts-2026-10-09.json).
QA directory:
`/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa/v4-water`.
Final frozen build: `contacts-edge-final`, PCK SHA-256
`d741cbcd17214a8670896a4da8e34c5a76b6d17c8f9f585794bfaf8f1e4330ab`.
It uses the existing patched runtime and native library recorded in the receipt;
no new engine patch is required by these scripts.

`tools/tests/water_surface.gd` compares the CPU query with the actual water
vertex shader, not another copy of the interpolation formula. On Compatibility,
Forward+ and Mobile, all 3,844 interior samples in each of four authored-water
states agree within 2 mm, with no missing coverage: 46,128 covered samples total.
The states include moving waves, waves disabled and scripted level offsets.
Reported zero error means below this image capture's quantization, not exact
real-number equality. Eight synthetic checks cover overlap ownership, holes,
negative coordinates, offsets, mesh replacement/removal, lava and release.

`tools/tests/water_interaction.gd` uses original human figures on real zone1
terrain with controlled presented poses. It checks standing/motion/turning,
entry/exit, high roots, hovering model bounds, full submersion, visibility/death,
flooding, the 16-contact cap, release, travel/loading/movie/LMP guards and actual
pause/1×/2× callbacks. A diagonal water-cell boundary remains a candidate for
the exact deformed-surface query. Final acceptance: **360 assertions**, across
headless and the three desktop renderer backends. This is not a full gameplay
route or a real host/guest session.

Settled empty-program and off/on/off captures are exact on all three backends.
Forced lava/swamp branch controls and rain/SSR controls under open/covered skies
are also exact. These classification controls do not establish broad artistic
coverage of whole swamp/lava maps. Fresh-cache Mobile initially changed 34
pixels (maximum 2/255) in the original water program and 30 (maximum 4/255)
after enabling the original rain/SSR path. Original/original controls reproduce
those startup changes; after settling, original/candidate/restored pairs match.
Do not attribute that transient to a contact regression or weaken the final
image comparison to hide it. Frozen diagnostic cameras disable physics
interpolation so CPU rays match the actual rendered camera.

The fixture's optional `--water-timing` mode runs an uncapped off/on/on/off
comparison at 1280×720, with 18 posed figures and 16 moving contacts. Linux
RTX 3090 samples showed controller medians around **1.31–1.35 ms** with contacts
enabled. Complete fixture-frame medians were about 2.0–2.12 ms enabled versus
0.81–1.40 ms off, depending on backend/pass. Draw counts stayed 325 on
Compatibility/Mobile and 586 on Forward+. Two-metre buckets reduced the earlier
stationary crowded update sample from about 2.0 ms to 1.3 ms while preserving
captures. The first sector build still cost roughly 5–7 ms in these samples.
These are fixture costs, not gameplay FPS or Android/web predictions. The Mobile
timing run overlapped another project's Godot process by its end; lower measured
GPU times under the slower CPU cadence do not establish a GPU optimization.

**Keep the option off by default.** Remaining acceptance includes broader
creature shapes/poses, large or differently sloped water bodies, sustained
co-op/play routes, camera distances and actual constrained-device cost. Existing
authored terrain uses axis-aligned transforms and immutable water meshes;
in-place editing of the same `ArrayMesh` is outside this cache's current contract.
The effect is an analytic rim/wake in shading. Wave-equation propagation,
river-current advection, refraction changes and waterfall shells/spray/mist
remain separate, unimplemented V4 work. Terrain caustics are implemented in the
follow-up below. V2 should next extend the existing terrain-details manager. The gameplay
handoff's U45 progression report remains first when starting the gameplay track.

## V4: optional underwater caustics — 9 October

The new **Underwater caustics** option (`gfx_water_caustics`, Remake group 15,
row 8) defaults **off on every platform** and requires Water and lava effects.
It animates sunlight patterns on eligible terrain beneath clear water. This
checkpoint uses the canonical checkout on top of `cae07dc`; protocol 13 and the
user's desktop continuous-sun policy remain unchanged. Nothing was installed
or published.

### Reference and implementation map

Read the reference at **R1 `0092dc6e1d7c4aab3f74644a79e9bfca11ecf293`** with
`git show`; the reference worktree remains at R0. Relevant locations:

- `Source/native_shader.h:689/745/757`: signed bed depth, live liquid-level
  shifts, and exclusion of the liquid surface itself from bed effects.
- `Source/native_shader.h:1655–1658`: positive-depth/non-emissive terrain
  admission, upward-normal and sunlight weighting, and bed-colour modulation.
- `Source/shaders/liquid_surface.hlsl:737–747`: two moving vein layers and
  depth attenuation. `Source/renderer_liquid.cpp:190–205` supplies game time.

The Godot implementation and its generated texture are independently authored:

- `game/src/game/fx/water_caustics.gd:15` builds a small, immutable two-metre
  coverage field from the actual nine-vertex water tiles. Each admitted texel
  requires a homogeneous clear-water material ring large enough to cover its
  entire filtering footprint at maximum horizontal wave displacement, including
  authored land XY offsets for type-4 liquid. The ring's minimum height minus
  the vertical wave bound gates lighting; its maximum height controls depth
  fade. Lava, swamp, emissive liquid and mixed-material edges are excluded.
  This is a conservative shading mask, **not an exact surface-height query**.
  The validated `water_surface.gd` query remains the contact/wake owner.
- `water_caustics.gd:81/111/134/151` provides four bounded metadata samples,
  two layers of a mipmapped 256² cellular vein texture, normal/sun/distance
  weighting, and the optional terrain shader source. Pattern strength fades
  with depth and from 35 to 65 m. It modifies terrain albedo in the existing
  opaque pass; original underwater attenuation and lighting/shadows still apply.
  Sun gating follows the reference's global sun strength, not a new optical
  focusing or per-pixel sunlight-occlusion calculation.
- `game/src/ei/terrain.gd:1028/1129/1397` owns the field, lazy shader variant,
  option restoration and phase bindings. Fractional texture translations use
  the terrain's existing scaled wave clock, so they pause with the world and
  avoid shader `TIME` or a discontinuous clock reset. Shared `level[64]` keeps
  scripted flooding live without rebuilding the field. Disabling the option
  or Water and lava effects restores the original shader and releases map data.
- `game/src/game/fx/terrain_color_cache.gd:44/72/81` selects the matching live
  shader for resident baked-colour sectors, copies the field and level uniforms,
  and synchronizes the phase. Animation is never baked into tile colours.
- `game_data.gd`, `remake_text.gd` and `gfx_detect.gd` add the applied option,
  English/Russian/German text, and conservative automatic-tier handling.

### Evidence and remaining limits

[water-caustics-2026-10-09.json](validation/water-caustics-2026-10-09.json)
records commands, source/pack/runtime hashes, all accepted results, process
observations and the rejected prototype. QA root:
`/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa/v4-caustics`.
The frozen `caustics-final` pack has SHA-256
`1e32c7e4522af89fccc23710f7fecf5fb2612173af9fd8507f9ad3d43713ea54`;
all 226 production script hashes match the validated source. It uses the
previously patched runtime; no new engine patch is required by this effect.

**347 assertions pass in twelve acceptance runs.**
`tools/benchmarks/water_bed_depth.gd` compares the shader mask with actual land
triangles and the previously GPU-validated deformed-water query. Two views on
each of zone1 and zone15, four independently reset wave/level states, and three
desktop backends give **48 configurations / 424,128 examined receiver pixels**,
with no detected dry-ground leaks at the diagnostic mask cutoff of 0.02. Each
view also has a nonempty lit region. These are coverage checks, not claims that
the conservative height equals the live surface.

`tools/tests/water_caustics.gd` passes on Compatibility, Forward+, Mobile,
headless, Compatibility's resident-colour path, and the second map's water-filled
canyon (`--caustic-zone15`). Paired off/on/off captures restore exactly. Frozen
phase is exact; animation is visible; no-sun and lowered-water controls are exact.
Forced lava/swamp metadata retains the original image, and emissive liquid is
excluded. Real callbacks verify tree pause, disabled travel worlds and 1×/2× timing.
The original unregistered-LMP assertion used a direct World→Terrain fixture;
the gameplay-hierarchy correction is recorded below. Field/texture weak references clear on disable;
resident materials change shader and follow the live phase correctly. The count
includes repeated assertions for individual resident materials, not 347 distinct
features. No complete co-op or gameplay route is claimed.

The first paired-vertex signed-depth prototype was **rejected**: subtracting
only a vertical wave margin still lit dry ground under sideways waves and at
raised water boundaries. Its frozen receipt includes 55 leaking pixels in one
wind view and 231 in one raised-water view. Do not restore that approximation.
Its initial fixture also carried wave state between cases; the receipt preserves
that limitation, and the final fixture resets each state and fixes both camera
foci before changing levels.

Map texture payload is 192 KiB on zone1 and 480 KiB on zone15, plus the shared
pattern; these are not whole-game memory figures. Draw counts stay 25 off/on in
the zone1 fixture and 29 in the zone15 fixture. Four metadata fetches, two pattern
samples and live uniform updates are additional work when enabled. Other Godot
processes overlapped many runs, so this checkpoint makes **no controlled GPU,
frame-time, FPS, Android or web performance claim**.

Keep the option off by default. The mask deliberately loses narrow pools,
mixed edges and detail on steep flows. It assumes immutable authored water
meshes and the existing axis-aligned map layout; arbitrary runtime geometry or
material edits require rebuilding/adapting it. Wider shorelines, deformation,
underwater-camera gameplay, artistic tuning and device cost remain open.
Wave-equation propagation, current advection, refraction changes and waterfall
shells/spray/mist remain separate V4 work. **V2 biome ground cover is next in the
initial visual sequence.** U45 remains the first gameplay investigation after
the renderer list.

### Terrain clock and deformed receiver correction — 9 October

Two integration defects were found while preparing V2 to share terrain time:

- Gameplay uses `GameWorld → EIMapScene → EITerrain`. The earlier direct-parent
  lookup missed the owning world and bypassed the LMP `can_tick` guard. Terrain's
  new `game_world()` resolves both gameplay and direct tool ownership. The
  corrected fixture fails against `8409adf` and passes with this lookup.
- A soft-ground footprint duplicates its entire sector material. Caustics on
  nearby wet terrain then froze at the copied phase. Terrain now forwards the
  live phase through `SoftGroundDeform.sync_parameter()` to its at most eight
  resident sectors. Option refresh still owns full material replacement.

`tools/tests/water_caustics.gd --caustic-soft-ground` uses zone15: a real dry
footprint at `(151.5,191.5)` changes the same sector as the underwater receiver
at `(155,173)`. It leaves authored types and water levels intact. The baseline
image differs from explicit phase binding by 50,487 pixels above 2/255; the
corrected Compatibility and desktop Mobile images match exactly. The option
disable/re-enable checks verify field release and renewed animation on those
copies. Zone1 has no eligible dry soft sectors in this fixture; the earlier
attempts there were setup failures, not evidence of the material defect.

**86 assertions pass** across the final headless, Compatibility and desktop
Mobile runs, including actual-hierarchy pause, travel holds and 1×/2× timing.
The final pack SHA-256 is
`32d990836a9bd78ab0ce8be66979d499c658956cd0bfbc752d5ccaea80332efa`;
all 226 production scripts match its export manifest. See
[clock/receiver evidence](validation/water-caustic-clocks-2026-10-09.json) for
the negative controls, commands, hashes and images. No new shader or default
policy change is involved. Full gameplay/device and broader deformation
acceptance remain open; other renderer processes overlapped these runs, and
no performance claim is made.

## V2: optional grass interaction and pausable grass wind — 9 October

This is the interaction stage of V2; **biome-specific cover remains next**.
The new **Grass interaction** option (`gfx_vegetation_interaction`, Remake →
Water and effects, group 15 row 9) defaults **off on every platform** and requires
Grass blades. Row 12 in World and textures is reserved for Original look; do
not put another option there. Visible living creatures part existing grass,
which gradually springs back. Crawling uses a longer contact envelope centred
on the presented body. No new simulation actors, save fields or packets are added.

### Reference and source map

At R1 `0092dc6e1d7c4aab3f74644a79e9bfca11ecf293`, read
`Source/renderer_ground_cover.cpp:2166–2193` for shown/grounded unit admission
and game-time recovery. `Source/ground_cover_interaction.h:24/37/66` covers
wind fronts, placement cells and recovery ownership. This adaptation is
independently authored; it does not port their D3D compute implementation.

- `game/src/game/fx/vegetation_interaction.gd:5/25/113/140` owns one 128² RGBA8
  pressure texture (64 KiB), half-metre world cells, a 64 m toroidal window,
  and at most 4,096 sparse history cells. Updates are capped at 20 per game
  second; empty recovered history performs no texture upload. Contacts ease
  in over 0.2 s and recover exponentially with a 0.55 s time constant. Short
  movement segments fill between samples; corrections over 2 m start a fresh
  contact rather than drawing a connecting trail. Moving the camera retires
  cells outside the window, preventing wrapped history from reappearing.
- `vegetation_interaction.gd:48/53/62/93` reads the world's visible registry
  after presentation and fog updates. Hidden, fogged, dead, invisible and
  off-screen actors supply no new contacts. Authored grass/slope/water/deck
  admission and actual presented part bounds reject airborne and elevated
  figures. Up to 32 nearby candidates receive pose queries; the initial scan
  still scales with the visible registry. Previously visible pressure may
  recover after its actor leaves visibility; it never follows that hidden actor.
  Scene/world pause, loading holds, movies and LMP holds stop history updates.
- `vegetation_interaction.gd:164/179` adds one linearly filtered vertex lookup,
  horizontal bending and tip compression to the existing grass shader. The
  influence fades at 27–30 m from the field centre. Native placement, colours,
  near/far meshes and native/script generation remain in their existing owners.
- `game/src/game/fx/terrain_details.gd:118/233/249` owns the optional field and
  material variants. Grass wind now uses the scaled terrain wave clock instead
  of wall time. The animated variants retain a `TIME*0.0` dependency solely so
  Godot refreshes cached local shadows; it contributes no visible motion.
  Wind-off, interaction-off grass uses the static variant. Do not remove the
  animation dependency merely because the visible phase comes from a uniform.
- `terrain_details.gd:291/509` expands scenery clearance and culling margin by
  the 0.35 m bend allowance. This keeps bent leaves out of nearby walls and
  includes displacement in visibility. Flooding/scenery invalidation clears
  history with the existing grass generation barrier. Disabling either the
  option or grass releases the pressure owner/texture and restores the base
  material. There is no second chunk manager.
- `game_data.gd:115/291/343`, `remake_text.gd`, and `gfx_detect.gd` provide the
  applied option, English/Russian/German text, original-look membership and
  conservative automatic settings.

### Validation, cost and remaining V2 scope

The reproducible fixture is `tools/tests/vegetation_interaction.gd`; add
`--vegetation-timing` for the bounded 32-character comparison and
`--ei-script-grass` to exercise the existing non-native generator. It uses
actual zone1 terrain and authored human standing/crawl poses under sun and
local shadows. It is not a complete gameplay or navigation route.

The accepted pack is in
`/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa/v2-vegetation/vegetation-accepted`.
Its PCK SHA-256 is
`b1d55d680a69500c33d028e637d2b9116fd554ed6d76434c375b62eff3e19c73`.
[Vegetation evidence](validation/vegetation-interaction-2026-10-09.json) records
source/runtime/native hashes, commands, results, images and the failed controls.
It uses the existing patched runtime, with no new engine or native-library patch.

**238 focused assertions pass** across headless, Compatibility, Forward+, desktop
Mobile and Compatibility's forced script generator. The unchanged
`tools/tests/grass_chunks.gd` adds **3,655 passing regression assertions** for
native/script data parity, immutable worker inputs and lifetime. All 227
production script hashes match the accepted export. These counts include
repeated backend/actor checks. Empty and off-restored images, held game time, real tree pause while wall time
advances, and local-shadow refresh controls are checked. The first shader lacked
Godot's animation dependency and left stale Compatibility shadows: 19 changed
pixels, maximum 5/255, after forcing an instance refresh. The corrected shader
matches that control. A separate early Mobile mismatch was reproduced in the
**unchanged initial scene** (411 pixels, maximum 7/255). Waiting for initial
rendering to settle removes it. Preserve the initial-versus-settled control;
do not relax pixel assertions to hide that startup difference.

The 1280×720 Compatibility sample with 32 posed figures measures about
**1.11–1.12 ms per active pressure update** on the desktop host. With the 20 Hz
cap it uploads 53 × 64 KiB in 2.667 supplied game seconds (about 1.24 MiB per
normal-speed game second). GPU viewport medians are about 2.00–2.02 ms off and
2.20–2.25 ms on. Total sampled draws are 3,928 off and 3,930 on; the changed
bounds/animation can add shadow/culling work despite using the existing grass
pass. These are fixture results, not a gameplay FPS gain or Android/web result.

Keep this off by default. The field has no per-unit vertex loop, but adds a
vertex texture fetch and maintains animated-shadow work while enabled, even
when the pressure history is empty. Further idle-path optimization, physical
Android/browser cost, wider creature sizes, lighting/normal quality, long camera
routes, reload acceptance, and motion smoothness at low frame rates remain open.
The current map/grass coordinate conventions assume the existing axis-aligned
map layout. Corpse pressure and persistent snow prints remain in their separate
owners. **Meadow flowers, dry tufts, tree litter, stones/dead bushes, swamp reeds,
shore/underwater cover, snow-region decoration, far-density thinning and shared
weather wind fronts are not implemented by this checkpoint.** Extend existing
TerrainDetails generation for those next; do not replace it with another grass
streamer. U45 remains first when the later gameplay handoff begins.

## V2 follow-up: optional dry-land biome cover — 9 October

`gfx_biome_cover` adds meadow flower patches, dry/sandy tufts, short snow straw,
broadleaf litter, conifer needles, twigs, small stones and sparse dead bushes.
It is **off by default on every platform**, in Remake → Water and effects, row
10. It works independently of Grass blades. Grass interaction can now bend
these flowers/tufts using the same pressure field; rigid litter remains rigid.
This is a visual addition with extra geometry and shadow work, not a speedup.

### Source map and placement contract

The reference remains **R1 `0092dc6e1d7c4aab3f74644a79e9bfca11ecf293`** in
`/home/llm2x/Documents/evil-islands-owned-renderer`. Read R1 with `git show`;
the reference worktree itself is still at R0 and has not been changed.

| Reference location | Adaptation and current implementation |
| --- | --- |
| `Source/ambient_particles.h:30–106` | Ground classes, authored tree families and zone context inform `game/src/game/fx/biome_cover.gd:28/45/145`. These are explicit model identities, not guesses from translated object names. Actual selected model parts are checked with `EIFigure.sways`; a `nafltr75` placement without its leafy crown contributes wood, not leaves. |
| `Source/ground_cover.h:248–295` | Patchy meadow flowers, dry tufts, sparse snow straw and stones become the seven bounded species in `biome_cover.gd:145` and `biome_cover_mesh.gd:106`. Densities and geometry are new, conservative Godot implementations. The original grass distribution/RNG is unchanged. |
| `Source/ground_cover.h:296–329` | Independent broadleaf/conifer/wood proximity fields become the 6 m tree index in `terrain_details.gd:282/320`, and `BiomeCover.tree_influence`. Snow has no broadleaf litter; the current Suslanger profile has no forest litter. |
| `Source/ground_cover.h` far-density rules and `ground_cover_interaction.h` | New cover shrinks selected instances smoothly between 18–28 m and all cover fades at 28–36 m. It shares the existing pressure/wind owner. Original grass retains its previous mesh LOD policy; weather wind fronts are still separate work. |

Important implementation locations in the canonical checkout:

- `game/src/game/fx/biome_cover.gd:55`: immutable packed-array and atlas copies;
  native triangle query when available, independent script fallback at line 76.
  The UV lookup follows the actual jittered triangles and rotated original
  atlas tiles. Generation never reads a live node from a worker.
- `biome_cover.gd:112/168/181`: dry-surface and footprint tests, deterministic
  candidates and scenery exclusion. Reject liquid coverage, roads, unknown
  terrain, ice, high rocks and overlying floors. Flower footprints also need
  painted green meadow pixels. Rigid litter follows the local surface normal
  and rejects nearby terrain that departs too far from that plane.
- `biome_cover_mesh.gd:5/64/106`: small opaque meshes, shared shader and
  species shapes. One merged surface is attached to each existing grass
  chunk, rather than a separate draw for each species. Wind and pressure mark
  shadow animation through `TIME*0.0`; visible motion uses the held game clock.
- `terrain_details.gd:124/510/544/582`: independent options, snapshot
  preparation, composite grass/cover jobs and main-thread mesh installation.
  Existing four-worker/80-chunk limits, camera queue, revision barriers and
  `water_changed()` remain the owners of lifetime. Empty cover creates no mesh.
- `terrain.gd:1109`: create TerrainDetails when cover alone is enabled.
  `vegetation_interaction.gd` now calls `TerrainDetails.vegetation_allowed`, so
  visible grounded creatures can press dry cover even with grass disabled.
- `game_data.gd`, `remake_text.gd`, `gfx_detect.gd`: applied option, original-look
  membership, English/Russian/German text and conservative automatic settings.
- `tools/benchmarks/biome_cover_census.gd`: read-only campaign/tree census.
  `tools/tests/biome_cover.gd`: placement, immutable workers, actual-map
  rendering, clearance controls, shader shadows, pause, reload and option tests.

Zone context comes from the owning GameWorld. Without it, map metadata is used
only when one zone matches; reused MPRs remain conservative until a world is
assigned. The LiA census observes `gipat2`, which currently gets general meadow,
dry and stone rules but does not inherit the explicit Gipat/Ingos litter
profile. A reused LiA `zone21` has only conservative stone cover in the detached
terrain fixture. Extend campaign profiles from authored context, not a guessed
map-name prefix.

### Evidence and limitations

[Biome-cover evidence](validation/biome-cover-2026-10-09.json) records accepted
runs, frozen tool/source hashes, images, failed development controls and exact
commands. The export is
`/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa/v2-vegetation/biome-validation`;
PCK SHA-256: `0a35c3dfd13cc69e4051bd09ef330da086325bb01cd6e1a16cac2344c44fe32a`.
It uses the same patched Godot runtime/native library as the interaction stage,
with no additional engine/native changes. The tests cover authored base-game
and LiA terrain, full-scene meadow rendering on three desktop backends,
regional dry/snow views and the script fallback. Snapshot tests also exercise
combined native grass/cover jobs while source terrain/images are mutated.

**17,852 cover assertions pass** across ten accepted runs, plus **3,655**
unchanged native/script grass assertions and **42** existing rendered
interaction assertions. These totals include repeated fixture and per-placement
checks. All **229 production scripts** match the accepted export manifest.
The Compatibility mixed-grass capture keeps the meadow flowers visible among
the original blades. Rigid forest litter remains fixed under pressure. Full
scene off/restored, held-time and forced-shadow-refresh image pairs are exact
in the accepted cases.

The early worker test caught mutable packed-array aliases; explicit copies fix
the mismatch. Cover-only loading also needed its own TerrainDetails creation
gate. The first release fixture called the missing owner and crashed; the
corrected fixture checks that owner before use. A forced-script fixture also
incorrectly requested a native job without a native field; it now follows the
supported fallback path. Those failed runs are not acceptance results.

The first full-scene pause mismatch was entirely in old tree crowns above image
row 123; off/on restoration had the same 21,042 changed background pixels.
The standalone tool had bypassed Game's foliage-wind controller. An unchanged
cover-off control reproduces that motion; disabling that existing wind input
gives exact cover pause/restoration comparisons. A desert camera also initially
sat behind a large rock. The fixture now checks the camera sightline against
terrain and scenery instead of accepting an invisible feature.

Enabling pressure expands scenery clearance to contain bent tips. Near walls,
this deliberately removes some tufts even with an empty pressure texture. The
fixture records that placement difference and compares the empty shader on
**identical geometry**. This must not be hidden by loosening a pixel tolerance.

The five-map native metadata sample builds 2,554 cover records in 392 sampled
chunks; median chunk generation is about 0.45–0.67 ms, with a 4.18 ms maximum in
that run. It does not include live scenery installation or GPU upload. These
are diagnostic CPU samples, not a frame-rate or device claim. Other Godot
processes were present for some rendered checks and were left alone; their
identities are in the receipts. No exclusive GPU performance result is claimed.

The new cover's far-density fade reduces visible/rasterized coverage but still
submits all mesh vertices; do not describe it as a measured vertex/draw saving.
The extra immutable terrain/atlas copies consume memory while enabled, and each
nonempty chunk adds a main draw and potential shadow draws. Android/browser
timing, memory and upload costs remain unmeasured.

**Remaining V2 work:** reeds/swamp banks, verified sea shores and underwater
plants, snow/sand mounds, wider species/Dead City/cave profiles, weather wind
fronts and actual submission-efficient distance LOD. The original cover-stage
image fixtures intentionally disabled soft-ground deformation. The follow-up
below adds root attachment; wider sand/snow gameplay acceptance remains open. Wider travel/streaming
routes and actor sizes also remain. Keep defaults off. U45 remains the first
gameplay investigation after the renderer work.

## V2 follow-up: cover roots on deformed sand and snow — 9 October

This follows `cbf09e6`. With **Biome ground cover** and **Soft ground** enabled,
cover now follows the drawn loose layer, compressed footprints and their fade.
Previously the new plants stayed at the original terrain height: snow could
bury short straw, and compression could leave roots above the surface. The
existing default-off cover option, desktop continuous sunlight and Android/web
held-sun fallback are unchanged. No new option or engine/native patch is needed.

### Reference and implementation map

At R1 `0092dc6e1d7c4aab3f74644a79e9bfca11ecf293`,
`Source/ground_cover_surface.h:4–19` shares drawn triangle heights between cover
and object contact. Lines 28–43 also apply trails to snow-pile geometry;
`Source/renderer_ground_cover.cpp:340–355` classifies snow and soft sand. The
remake reuses its own existing deformation and exact surface-query contract.
Snow-pile geometry and the reference's D3D compute path are not implemented here.

- `game/src/game/fx/biome_cover.gd:186`: `surface_anchor` records the supporting
  authored triangle, including XY offsets, its side and barycentric weights.
  Its immutable loose-tile mask comes from actual tile types. This search runs
  during chunk generation, not in every rendered vertex. Hard areas get an
  inactive marker. Competing/folded triangles and exact shared-edge roots near
  loose ground are omitted conservatively; deformation could otherwise change
  which overlapping surface is highest. Ordinary sampled map counts are unchanged.
- `biome_cover_mesh.gd:11/88`: four float32 `CUSTOM0` values carry each anchor.
  The shader reads three original vertices and calls `query_elevation`, after
  wind, pressure and distance fading. Whole plants/litter translate vertically
  at their roots; their original orientation/normals remain. This does not make
  every point of a wide leaf or stone conform to a narrow footprint.
- `ground_surface_shader.gd:181/262`: exposes the existing triangle query as
  `TRIANGLE_QUERY`; `QUERY_SHADER` still adds the full scenery search. The
  actual installed tile table chooses original versus 16-way subdivided
  triangles. Pending jobs therefore cannot move cover before terrain changes.
  `SoftGroundField` supplies its existing texture array, layer table and clock;
  cover adds no track image, per-frame geometry upload or GPU readback.
- `game/src/ei/terrain.gd:731`, `ground_surface_data.gd:20/65`, and
  `ground_contact.gd:97`: a weak per-terrain cache shares one geometry resource
  among enabled consumers. Cover alone skips contact-light normals and upper
  bounds. A later contact bind adds them while preserving the bound vertex RID.
  Turning off the last consumer releases the resource. If contact has already
  upgraded the snapshot, its normals remain until that shared resource releases.
- `terrain_details.gd:250/523/598`: binds after the soft-ground owner exists,
  installs the custom mesh format, expands the culling margin by 0.30 m, and
  drops material/field references at stream/rebuild barriers. Maps containing
  no loose tile allocate no cover geometry texture. Disabling soft ground
  selects the original cover shader and releases the optional texture bindings.
  Water changes reuse the existing placement rebuild. `TIME*0.0` preserves
  local-shadow invalidation while visible motion uses the existing game clocks.

### Validation and costs

The reproducible fixture is `tools/tests/biome_cover_surface.gd`. It loads full
authored zone11 and zone15 scenes, places actual generated cover, installs real
footprints and compares GPU root heights with an independent oracle built from
the **currently drawn mesh arrays**. Options include `--surface-zone=gz15h`,
`--ei-script-grass --surface-script-mesh`, and `--surface-timing`.

The final export is
`/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa/v2-vegetation/cover-surface-final`.
PCK SHA-256:
`bdef5155bb519af2ccfbeaee3b095f0f3f7b9f238d1606c32e0413a7bdda7e00`.
All 229 production script hashes match the final export manifest. The receipt
records the earlier matrix pack and the single formatting-only source difference. The
[surface evidence](validation/biome-cover-surface-2026-10-09.json) preserves
commands, frozen tools, runtime/native hashes, images and failed controls.

**59,387 assertions pass** across the seven-run matrix and a final 35-check
ground-contact rerun after normalizing one indentation tab. Totals are 49,384
new surface assertions, 6,278 existing cover checks, 70 ground-contact checks
and 3,655 existing grass checks. These include repeated per-point/per-backend
checks, not 59,387 unique unit tests. The GPU validates **45,044 positive root
samples within 2 mm** of the drawn triangle plus the existing **8 mm root offset**;
another 4,096 deliberately wrong heights all fail the diagnostic as expected.
Compatibility, desktop Mobile and Forward+ pass; the Compatibility snow run
also forces both script generators. Coverage includes pending/installed work,
fading/expiry, sector borders and eviction, clear/reallocation with stable
texture RID, shared-contact upgrade, real water-level rebinding, option
round trips, combined wind/pressure/tracks and tree pause. Final restored and
shadow-refresh images are exact. No tolerance was relaxed for startup differences.

Development failures are retained in the receipt. One fixture incorrectly
inherited `ALWAYS` into its world, a probe assumed render-target Y orientation,
and an absent water material was initially used. The combined wind fixture
also needed to restore its water clock before image comparisons. A first
Mobile image had 265 differing background pixels compared with later restored
images; added setup/settled controls pass, but its precise initial-state cause
is not established. One Vulkan launch failed before the test started and the
single retry passed. None is reported as a passing production test or a fixed
engine defect.

Cost: 16 additional bytes per cover vertex, plus one 16-byte-per-grid-vertex
texture on maps with loose ground and a one-byte-per-tile placement mask. The
sampled snow map uses 3,160,080 bytes for that texture; the sand map uses
1,977,360. Contact can share it. Cover alone avoids the initial design's second
normal texture and bound preparation. Final complete cover preparation took
about 51–102 ms in these desktop fixtures; this includes other snapshot work,
not just attachment. Local shadows remain animated when deformation is enabled,
even with no current tracks. Single-order desktop viewport timings are noisy
and establish no speedup or Android/browser performance result. Defaults stay off.

Next V2 work is shore/swamp/underwater cover, snow/sand mounds, richer authored
regional profiles, shared weather wind and actual submission-efficient LOD.
Wider camera/travel routes, rigid litter edges, device costs and artistic
acceptance remain open. U45 still starts the subsequent gameplay track.

### V2 follow-up: river and swamp banks, conservative sea debris

Implementation checkpoint after `f2b952b`; source remains on
`fix/catacomb-coop-deck`. The existing `gfx_biome_cover` option now adds sparse
reeds to inland banks and cattails to swamp banks. It remains **off on every
platform**. New wrack and shell geometry/rules require actual sand beside a
verified sea; their coverage at this checkpoint is synthetic only. Underwater
plants are **not implemented** by this change.

Reference revision is still **R1
`0092dc6e1d7c4aab3f74644a79e9bfca11ecf293`** in
`/home/llm2x/Documents/evil-islands-owned-renderer` (read-only). The relevant
locations are `Source/ground_cover.h:327-352` (swamp, river and sea rules),
`Source/renderer_ground_cover.cpp:390-570` (admission) and `:697-728`
(wet/shore fields). This is an independently authored adaptation to the existing
Godot terrain streamer, not a new cover manager or a port of the compute pass.

**Implementation map**

- [biome_cover.gd:86](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/game/src/game/fx/biome_cover.gd:86):
  `_prepare_shores` reads each authored `Water_x_y` mesh once when the immutable
  cover snapshot is built. It keeps submerged centre vertices from homogeneous
  water/swamp tiles, applies current scripted water offsets, and excludes lava,
  emissive liquids, mixed owners and water covered by a floor. Positions and
  classification are packed into nearby 8 m chunk buckets; workers retain no
  live water node, material or scene reference. The existing water/scenery/option
  barriers join jobs and replace this snapshot.
- [biome_cover.gd:126](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/game/src/game/fx/biome_cover.gd:126):
  `shore` and `bank_weights` use the nearest admitted water centre and its level.
  Swamp reeds taper over a 3 m band, cattails over 2.2 m, inland reeds over
  1.6 m. These are approximate bands based on the 2 m lattice with a 1 m
  allowance, not exact wave/collision coverage. Roots must remain dry and only
  0.06–0.8 m above nearby mean water, avoiding high cliffs. Stable 4 m patches
  leave gaps instead of making uniform rows. Cave/unknown contexts stay excluded.
- [biome_cover.gd:329](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/game/src/game/fx/biome_cover.gd:329):
  `bank_records` has a separate random sequence. The old seven-species sequence
  remains fixed, so adding kinds does not reshuffle existing flowers or litter.
  The existing dry footprint, atlas-alpha, floor, slope, scenery and unique
  supporting-triangle checks still apply. A 2 m vertical exclusion contains the
  tallest scaled cattail plus the possible 0.30 m soft-ground lift. The existing
  pressure admission also permits reeds on otherwise bare ground.
- [biome_cover_mesh.gd:134](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/game/src/game/fx/biome_cover_mesh.gd:134):
  `reed` builds a stalk with four curved leaves and either a seed head or a
  capped cattail cylinder; `shell` makes a small ridged fan. `build` also adds
  folded wrack ribbons. Reeds/cattails use existing wind and pressure; debris is
  rigid and aligned to its supporting plane. All species share the existing
  opaque chunk mesh, lighting, root attachment and shadow program. No new
  shader sampler, material, per-frame manager or native/engine patch was added.

**Important authored-data limitation:** `EITerrain.SEA_MATERIALS` still confirms
only internal `zone1` material 2 as sea. Do not infer sea from map borders or
waves. The starting map's dry sea coast is ground type 1, not sand type 3;
R1's `Source/terrain_tile_presets.h` entry `Zone1` likewise has no Sand family.
The reference's broader sand-corner support lives in
`Source/terrain_tile_blend.h:161-170`; it is not imported here. Therefore this
stage deliberately places **no wrack/shells on the observed zone1 coast**.
Do not describe those two species as visually accepted on a real sandy beach,
or relabel ordinary ground based on colour. A verified sandy sea map/profile
and rendered acceptance are still needed.

**Validation:** [biome-cover-shores-2026-10-09.json](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/validation/biome-cover-shores-2026-10-09.json)
records **16,269 passing assertions in seven final runs**: focused native/script
placement, Compatibility cattails, desktop Mobile/Forward+ reeds, and existing
base/Lost in Astral cover regressions. The fixture uses complete authored zone1
scenery. Settled empty-pressure, pause, forced shadow refresh, rebuild and
off-restored image comparisons are exact on all three desktop renderers.
All **533 sampled existing dry records** across zone1/zone11/zone15 match the
previous `f2b952b` export byte-for-byte in both current sampler modes. The
isolated placement scan finds 72 reeds and 17 cattails in zone1 before scenery
exclusion; these counts are not full gameplay population measurements.

Tests and reproducible controls:

- `tools/tests/biome_cover_shores.gd`: actual liquid/sea identity, dry roots,
  excluded materials/cliffs, mesh envelopes including soft-ground lift, tall
  overhangs, immutable workers after water mesh removal/source mutation,
  flood/drain/restore, covered water, and authored native/script placement.
- `tools/tests/biome_cover.gd`: existing renderer/lifecycle fixture; accepts
  `--cover-kind=7` for reeds and `=8` for cattails. The empty-pressure material
  transition now receives the same settling interval as the initial on-state.
- `tools/benchmarks/biome_cover_dry_fingerprint.gd`: runs against both old and
  new packs; `biome_cover_shore_census.gd` records the authored classification.

Final export is `.../owned-renderer-improvements-20261008-qa/v2-vegetation/cover-shores-accepted`.
Pack SHA-256 is
`92b827a43b610e9dcab07ad3f3a97d8cd1644559008c927287321fecdb4a9ce0`;
all 229 current production script hashes match its manifest. The receipt links
the exact frozen tools, runtime/native hashes, commands, logs and captures.
The unchanged patched runtime is required for the existing native Mobile path.

A first Mobile empty-pressure capture differed by seven pixels, maximum 3/255.
Holding the same shader/geometry for 160 frames restores exact agreement;
removing the y-deformation arithmetic did not remove the initial residual.
`shores-empty-probe` preserves that comparison. This corrects fixture settling,
not a proven engine or arithmetic defect. Earlier fixture-only type/membership
errors are recorded in the receipt. No production failure was hidden by a
relaxed image tolerance.

**Cost and remaining work:** packed shoreline index payloads are 362,048 bytes
in zone1, 247,440 in zone11 and 115,856 in zone15, excluding container overhead.
Sampled bank-record generation in zone1 is about 0.182 ms median / 0.643 ms
maximum with the native ground sampler and 0.621 / 1.343 ms with the script
sampler. These are desktop construction samples, **not frame time or an
Android/web benefit**. Additional populated chunks can add draws/shadow work;
distance shrinking still submits vertices. Fine tuning density/shape, long
camera routes, physical devices, actual sandy shores, underwater lighting and
plants, mounds, richer biome profiles, shared weather wind and efficient LOD
remain open. Next V2 implementation is underwater cover with correct original
water attenuation, then the remaining regional/deformation work. Gameplay U45
still begins the subsequent gameplay track.

Desktop sunlight stays continuous on all renderers. Holding remains the
Android/web fallback pending a better measured replacement. Nothing was
installed, published or changed in original assets/saves/network protocol.

### V2 follow-up: optional underwater vegetation and mean-depth lighting

Implementation checkpoint after `a0c82da`, 9 October. The existing, default-off
`gfx_biome_cover` option now includes short seagrass, taller kelp-like grass and
small rigid shells under **verified sea water**. This is independent geometry
using the existing TerrainDetails workers and merged chunk surfaces. The
reference remains read-only R1 `0092dc6e1d7c4aab3f74644a79e9bfca11ecf293`:
`Source/ground_cover.h:346-349` supplies the sea/depth rules;
`Source/renderer_ground_cover.cpp:478-570` the admission context and
`:1224` (`make_seagrass`) the curved-blade idea. Density and geometry here are
adapted to the remake, not a direct port or a claimed performance improvement.

**Implementation map**

- `game/src/game/fx/biome_cover_water.gd:9`, `add_tile`: copies homogeneous,
  non-emissive water geometry and current scripted offsets into immutable
  records. It keeps no scene, material or clock references. An 8 m chunk index
  avoids running sea placement candidates in wholly inland chunks.
- `biome_cover_water.gd:37/72`, `sample`/`ceiling`: exact original mean-water
  triangle planes, with a direct regular-grid path and barycentric fallback
  for jittered vertices. The ceiling requires a complete same-material patch
  over the leaf footprint plus maximum horizontal wave movement, and uses
  its lowest vertex minus vertical wave drop. Missing or mixed water rejects
  the plant. This is a conservative height envelope, not a live wave query.
- `biome_cover.gd:88/364/376`: the existing water snapshot admits only
  `EITerrain.SEA_MATERIALS[resource_prefix]`; currently this means **zone1,
  material 2**, not every river or map edge. `sea_surface` checks the actual
  seabed triangle, floor exclusion, original atlas opacity and slope.
  `sea_records` uses an independent deterministic random stream. Short plants
  occupy roughly 0.4–3.5 m mean depth, tall plants 1.5–6.5 m, and shells under
  2 m. Sparse patches, four footprint probes, unique root anchors and existing
  scenery exclusions still apply. Plants shorten to fit below the worst-wave
  ceiling, reserving possible 0.30 m soft-ground lift; tilted shell height is
  included. They do not emerge above the surface to satisfy a density target.
- `biome_cover_mesh.gd:8/103/196`: five curved ribbons with three segments make
  each grass tuft; shells reuse the ridged, ground-aligned geometry. CUSTOM1
  stores each vertex's nominal water plane and depth coefficient. After motion
  and root attachment, the shader sets `ei_k=min(depth²/(15*(1-alpha)),4)` for
  the existing ambient/sun/point-light formula and attenuates extra leaf
  transmission. Emissive water is excluded, so `ei_e` remains zero. Underwater
  vertices ignore dry-ground pressure. Wind still uses the terrain-owned clock.
- `terrain_details.gd:267`: select the aquatic shader variant for sea maps.
  Existing job barriers, option/water rebuilds, chunk bounds, culling and
  cleanup own the feature. No additional sampler, GPU texture, per-frame
  manager, engine patch, navigation data or network state is introduced.

**Validation and limits**

[biome-cover-underwater-2026-10-09.json](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/validation/biome-cover-underwater-2026-10-09.json)
records 307,299 passing assertions in ten final runs. The focused test
`tools/tests/biome_cover_underwater.gd` compares authored planes with the
independent `WaterSurface` query across zone1, including flood/drain/restore,
source lifetime, shape envelopes and native/script sampling. Its GPU test
executes the actual attenuation snippet: 12,288 positive vertex probes pass on
Compatibility, desktop Mobile and Forward+, and 3,072 deliberately incorrect
probes fail as intended. These are factor checks, not a pixel-perfect oracle
for the entire lighting pipeline. Full-scene checks separately exercise each
species, pressure exclusion, pause, shadow refresh, rebuild and off restoration
with original water. Base-game/Lost in Astral and bank regressions pass. All
535 sampled existing dry/bank records across three maps match the prior pack.

The 192-chunk metadata scan, without full scenery exclusion, emits 872 short
plants, 173 tall plants and 32 shells at the baseline level. The sea snapshot
contains 3,329 admitted tiles: its copied vertex payload is 359,532 bytes,
excluding dictionary/array headers and the chunk index. Sea-map cover meshes
add **16 bytes per vertex**, including zero entries for dry cover: 1,781,952
bytes over that scan. Native-sampler builds have medians 0.855–0.896 ms and
maximum 8.051 ms; script-sampler medians are 1.654–1.692 ms and maximum
10.281 ms. These are worker build samples, not frame-time, FPS or device claims.

Lighting deliberately uses mean planes rather than moving wave geometry.
Horizontal sway can cross a non-coplanar water triangle: the +0.65 m flood
fixture observes up to **0.05254 m** of plane-extrapolation error (268 non-flat
probes), while sampled baseline/drain states are flat. Treat exact animated
water lighting and its cost as future work. Existing broad triangular water
patches also reproduce with cover disabled in the old `a0c82da` pack; captures
and controls are retained, without claiming their cause or repair.

**Enhanced-water limitation found during this checkpoint:**
`--cover-water-fx --cover-kind=13` passes draw/pressure/shadow controls but fails
pause, rebuild-image and off-restoration checks. The existing
`EITerrain.WATER_FX_SHADER` still uses shader `TIME` for foam, normal maps and
rain rings, advancing during SceneTree pause and changing later comparisons.
Keep this failing run. Resolve the water clock with a separate before/after
fixture before claiming enhanced-water pause acceptance; do not suppress the
assertions or change cover defaults to hide it.
The subsequent water-clock correction below resolves this failure; the
original failed captures remain part of the underwater checkpoint's evidence.

Final pack: `.../owned-renderer-improvements-20261008-qa/v2-vegetation/cover-underwater-accepted`,
SHA-256 `6427d895a7ee87284fe38bbcd5a8a27a0d285ad19e7d1ca4aec6f15f5960a358`.
All 230 production scripts match its export manifest. Frozen tools, commands,
runtime/native hashes, failed development cases and captures are in the receipt.
No installed build, original asset or save was changed. Cover remains off.
Mounds, richer campaign/atlas profiles, shared weather wind, actual submission
LOD, long routes and Android/browser measurements remain open; U45 still starts
the subsequent gameplay track.

### V4 correction: enhanced-water details follow the terrain clock

Follow-up to `ff9f382`, 9 October. Enhanced water previously kept scrolling
normal maps, foam, rain rings and lava detail while SceneTree pause or an
inactive/LMP-held world stopped the actual water geometry. The underwater
cover fixture exposed this separate issue.

`game/src/ei/terrain.gd:567`, inside `WATER_FX_SHADER.fragment`, now derives
`water_time` from the existing per-material `wave_ticks` value using
`EIWaterWaves.TICK` (0.055 seconds). All seven former shader `TIME` references
use this value. `_update_wave_parameters` already publishes it, so there is
no new uniform, callback, allocation or texture. The existing owning-world
lookup and scheduling gates govern geometry and surface detail together.
Original-water shading, sea-cover rules and desktop sun policy are unchanged.

`tools/tests/water_detail_clock.gd` freezes wave geometry and observes actual
water rendering in a World → Map → Terrain scene. Advancing only terrain time
by seven seconds changes the image; resetting it restores the image exactly.
SceneTree pause, a disabled world and an unregistered LMP world each hold both
the CPU clock and the image. A real-time interval checks 1x/2x progression;
the water-option round trip preserves phase. The test disables viewport
physics interpolation to isolate the surface and checks initial stability.
The same frozen test fails four rendering assertions on the prior `ff9f382`
pack while its CPU holds pass, demonstrating the old clock mismatch.

See [water-detail-clock-2026-10-09.json](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/validation/water-detail-clock-2026-10-09.json)
for all commands, hashes, captures and results: **110 assertions pass in seven
final runs**. Clock/image checks cover
Compatibility, desktop Mobile and Forward+; the complete enhanced-water cover
fixture and existing caustics regression provide integration coverage. The
initial fixture mistakes (pause inheritance, assuming frame count implied a
fixed elapsed time, and inherited physics interpolation) are recorded rather
than counted as product regressions. No Android/browser performance or broad
liquid/route acceptance is implied.

The final clock-fix pack is `.../v2-vegetation/water-surface-clock`, SHA-256
`3bfca3109fa9a98776f06aba30425f5db8d556f47b301e482783ac65f8c90455`;
all 230 production scripts match its manifest. It uses the unchanged patched
runtime/native library recorded in the receipt. Installed builds and defaults
remain unchanged. Continue V2's remaining mounds/profiles/wind/LOD work and
the renderer handoff, then start the gameplay handoff with U45.

### V2: optional snow and sand mounds; Forward+ shader lifetime correction

Follow-up to `bcd48d5`, 9 October. The existing default-off `gfx_biome_cover`
option now includes sparse snow piles in Ingos and lower sand piles on verified
soft-sand atlas slots. Mounds use the original painted terrain material and
compact into the actual footprint surface. No gameplay height, navigation,
save format, desktop sunlight policy or default option changed.

**Reference provenance:** use `git show` at R1
`0092dc6e1d7c4aab3f74644a79e9bfca11ecf293`; these files are not all in the
checked-out R0 tree. `Source/ground_cover.h:319–326` defines the snow/sand
rules, `Source/ground_cover_snow.h:10–30` the irregular dome, and
`Source/ground_cover_surface.h:32–52` the terrain/trail relationship.
`Source/renderer_ground_cover.cpp:343–355,567,623,729–809` contains soft-sand
admission and vertex deformation/shading. `Source/terrain_tile_blend.h:193–211`
names the three soft-sand families; `Source/terrain_tile_presets.h` credits
editor metadata from `ei-mapper-endurance` commit `af24d45`. The reference
checkout remains clean at R0 `d529d14e9bf3c960833a9d9633786fc4588ec6d2`.

Implementation entry points in the canonical checkout:

- `game/src/game/fx/biome_mounds.gd`: immutable placement mask/normal snapshot,
  seeded candidates, full-footprint admission, cropped terrain-lattice geometry
  and two cached shaders. Each 8 m chunk admits at most two piles / 4,096
  vertices. Snow requires Ingos and original tile type 9/12; sand requires
  type 3 plus a verified atlas slot. Water, mixed materials, folded/steep
  triangles, excessive height range and neighboring scenery exclude a pile.
- `game/src/game/fx/biome_sand_tiles.gd`: 27 exact original image fingerprints,
  with 287 admitted full soft-sand slots across six profiles. The identities
  use canonical 512×512 RGBA8 pixels without mips. All four corners must be
  `Sand / Yellow`, `Sand / Dark` or `Sand / Common grayish`. Unknown, modified,
  mixed, wet, paved and other sand families remain unclassified. These rules
  classify mounds only; they do not finish the separate beach-debris audit.
- `tools/benchmarks/biome_sand_metadata.py`: reproducible generator reading
  pinned reference metadata and the original-atlas census. The collector,
  census, generation command/hashes and byte-identical regeneration are in
  `.../owned-renderer-improvements-20261008-qa/v2-vegetation` and the receipt.
  No original texture bytes are embedded in source.
- `game/src/game/fx/biome_cover.gd`: publishes a separate `mounds` payload through
  the existing chunk job. Existing cover records and random streams remain
  intact. Direct builder calls retain their supplied scenery exclusions.
- `game/src/game/fx/terrain_details.gd`: gathers neighboring exclusion buckets,
  binds the original/HD terrain material and existing optional surface data,
  and installs receive-only `BiomeMounds` meshes through existing worker,
  streaming, invalidation and shutdown paths.
- `tools/tests/biome_mounds.gd`: real World → Map → Terrain fixture and GPU
  vertex-height comparisons against an independently indexed installed terrain
  mesh. Pass `--mound-oracle=/absolute/path/to/frozen/biome_cover_surface.gd`;
  the receipt identifies the frozen copy and its hash. `--mound-zone=gz15h`
  selects sand; default `gz11k` selects snow. HD/detail and script fallbacks
  are explicit arguments in the recorded commands.

The dome uses the reference's irregular radial falloff, with smaller/sparser
placement. Its topology is a subset of the original triangles subdivided 16
ways, preserving rotated atlas UVs. Every vertex queries the actual installed
terrain surface; pending dense-mesh work cannot compact a pile early. Existing
shared track texture and recovery clock lower its thickness, and buried
fragments reveal the trench. No second trail field, texture readback or
per-frame vertex upload is added. Soft-ground off releases the optional surface
holder and uses baked original heights. Returning to a cached shader also
refreshes Gfx specialization, preventing the terrain from remaining compiled
for the prior soft-ground option.

The implementation preserves painted texture detail rather than the reference's
smoothed center colour. It shares existing berm deformation rather than adding
a separate mound-volume conservation model. Distance fading at 24–32 m lowers
the pile; **it does not remove geometry submission**. Actual submission LOD and
memory/route/device acceptance remain open.

See [biome-mounds-2026-10-09.json](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/validation/biome-mounds-2026-10-09.json)
for frozen source/runtime/pack hashes, commands, images and retained failures.
**8,782 assertions pass across 11 final runs**, including repeated engine
controls. There are 23,560 positive GPU vertex samples within 2 mm of the
independently evaluated surface, 4,712 deliberately wrong samples detected,
and 1,164 exact overhead trench-floor pixel comparisons. Tests cover pending
work, compaction/recovery, pause, clear, water invalidation, option restoration,
worker snapshots, HD/detail, native/script sampling and base/Lost in Astral
regressions. All 879 sampled pre-existing cover records, kinds 0–13, retain
their prior hashes.

**Mobile restoration limitation:** whole-scene restoration passes on the tested
Compatibility and Forward+ scenes. Mobile's explicit
`--mound-region-restoration` run checks a conservative projected mound area,
which restores exactly, and still records full-frame differences. After a
soft-ground round trip/rebuild, 165 distant tree pixels differ, eight by more
than 2/255 and at most 4/255. `tools/benchmarks/terrain_option_restore.gd`
reproduces a comparable 47-pixel residual with the old `bcd48d5` pack and no
cover. Initial images and signed residuals differ between that control and
candidate; the larger intermediate residual is **not attributed or resolved**.
The prior strict failed run is preserved. Do not label these scoped checks a
whole-scene Mobile pass or enable defaults on their strength.

Construction cost remains material: for 25 sampled snow chunks, eight active
chunks produce ten mounds / 6,222 vertices. Precomputing shape values once per
lattice point reduces the sampled active-chunk median from 13.024 to 5.486 ms
and maximum from 24.721 to 10.256 ms, with the same selected mesh hash. The
before timing pack still fails the subsequently fixed direct-builder scenery
check and is not counted among passing runs. Final sand samples take roughly
6.9 ms per active chunk. These are worker construction measurements, not frame
time or a demonstrated FPS gain. Long routes and actual Android/browser cost
must inform density/default decisions.

**Required Forward+ engine correction:** the first warm separate-thread run
passed, but repeating with fresh shader caches exposed 50 wrong-thread shader
frees and 50 leaked shader RIDs. The game assertions alone did not catch this.
`engine_patches/godot-4.7/forward-shader-recompile-lifetime.patch` moves
`pipeline_hash_map.clear_pipelines()` to the beginning of
`SceneShaderForwardClustered::ShaderData::set_code`, before mutable shader and
version state changes. The shared compiler mutex was already correctly scoped.
This is the same lifetime ordering needed by the earlier Mobile patch; the
Forward+ patch changes no shader equations or cache policy. It applies exactly
to the pinned Godot `5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88` source.

The rebuilt Linux runtime passes cold-cache Forward+ with both safe and
separate rendering threads, plus cold Compatibility/Mobile controls, without
shader errors or leaks. All 69 paired captured images are exact across the
old/new runtime comparison. The PCK, native library and frozen fixture are
unchanged in each pair. The simpler old-pack Forward+ option controls did not
reproduce the failure, so do not claim that baseline reproduction. The patch
is the eighth common engine patch in the template README; installed templates
and platform packages have not been updated.

Final application export: `.../v2-vegetation/cover-mounds-final`, PCK SHA-256
`4bc9b171e4e5bd9eec047d8296593fe3042512152cacfb0ffdfd15e6c5e9fdea`;
all 232 production scripts match its manifest. Use the paired
`.../v2-vegetation/cover-mounds-engine-final` runtime for further tests,
SHA-256 `090f2254527771465e745bb887386978dfca069ef1943b3b9bcadcad1a377a44`.
The native library is unchanged. No release, installed build, original asset
or save was changed. Continue the remaining renderer work; U45 remains first
when the gameplay track starts.

### V2: authored coastal habitats and beach-debris acceptance

Follow-up to `da1c325`, 9 October. The default-off cover option now recognizes
the island sea on **zone7, material 0**, and the open coast on **zone8, material
4**. These are the first verified authored sandy beaches for the existing
wrack/shell rules. The same immutable sea snapshots also admit the existing
underwater species. Zone8's connected material 5 remains an inland channel;
zone1 material 2 keeps its prior classification. Density, meshes, placement
exclusions, defaults and desktop sunlight are unchanged.

Reference R1 `0092dc6e1d7c4aab3f74644a79e9bfca11ecf293`:

- `Source/renderer_ground_cover.cpp:1331–1351`, `ground_cover_sea_mask`, labels
  edge-connected components with at least 2,048 open-water tiles as sea. This
  is a heuristic, not an authored ocean tag. `update_ground_cover_maps` uses
  it around line 1720. Our diagnostic used this to identify candidates, then
  inspected actual maps and water-material ownership. Directly copying it
  would combine zone8's coast and inland channel.
- `Source/ground_cover.h:327–352` contains shore and underwater cover rules;
  `Source/renderer_ground_cover.cpp:510–570` contains beach masks and height/
  slope admission. `Source/terrain_tile_blend.h:161–170` also permits atlas
  slots containing any sand-family corner. That wider atlas rule is **not
  implemented by this checkpoint**. The soft-sand mound family test at
  lines 193–211 is separate and must not be substituted for beach identity.

Implementation entry points:

- `game/src/ei/terrain.gd`, `SEA_MATERIALS`: the three explicit cover habitat
  profiles. New `SURF_MATERIALS` retains only zone1 material 2; `_build_surface_data`
  uses it for breaking surf/ripple strength. Extending cover habitat therefore
  does not enable unvalidated surf on new maps.
- `game/src/game/fx/biome_cover.gd`, `_prepare_shores`: existing sea snapshot
  and shore-channel consumers. Its dry type-3 sand, height, slope, footprint
  and scenery rules are unchanged. There is no new streamer or worker path.
- `tools/tests/biome_cover_shores.gd`: actual zone7/zone8 material and beach
  admission, inland-channel separation and unchanged surf controls. Reports
  whether native sampling or `--ei-script-grass` was actually active.
- `tools/tests/biome_cover.gd`: `--cover-kind-only` isolates one species in the
  existing authored World/Map/scenery fixture. Beach search visits every chunk
  because zone8's only admitted shell is in an even chunk. The synchronous
  `choose_cover` helper releases temporary snapshot references before awaits.
- `tools/tests/biome_cover_underwater.gd`: `--underwater-map=zone7|zone8` selects
  literal expected water owners and independently checks original water
  geometry, shader attenuation, flood/drain/restore and snapshot lifetime.
  Zone8 scans all chunks to retain the original 1,024-probe minimum.

The [coastal receipt](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/validation/biome-cover-coasts-2026-10-09.json)
records frozen tools, commands, hashes, images and retained failed controls.
The QA root is `.../owned-renderer-improvements-20261008-qa/v2-vegetation`.
`coast-components-base` records the component census; `coast-overviews` shows
actual maps; `coast-materials-unfogged` distinguishes zone8's water owners.
The earlier material-color view was obscured by fog and is not identification
evidence. The original reference checkout remains clean at R0.

Before complete scenery exclusions, the full bank scan admits 20 wrack and 58
shells on zone7, and one shell on zone8. Full authored render fixtures retain
two wrack or ten shells in the chosen zone7 views, and that shell on zone8.
These deliberately sparse results are not grounds for weakening footprint
checks. Compatibility, desktop Mobile and Forward+ captures verify visibility,
rigidity under pressure, pause, rebuild, shadow refresh and exact off restoration.
The species-only fixtures do not establish full mixed-cover visual acceptance.

Native/script shore distributions agree, with all 865 sampled prior dry-cover
records unchanged from the previous pack. The prior pack fails exactly the
five new coastal presence/snapshot assertions. GPU attenuation checks on both
new maps pass 8,192 positive samples and detect all 2,048 deliberately wrong
samples. Eight original/enhanced-water overhead/shore captures with cover off
are byte-identical between old and new packs on Compatibility. Existing large
triangular enhanced-water patches at zone8's outer edge are visible in that
unchanged baseline; this change does not fix them.

**Remaining limits:** the sea snapshots contain 21,605 tiles on zone7 and 5,312
on zone8. The existing shore-index payloads are about 1.44 MB and 0.56 MB,
excluding container overhead and sea snapshots. Underwater custom attributes
still add 16 bytes per cover vertex on these maps. No memory/FPS improvement or
Android/browser acceptance is claimed. During the artificial +0.65 m flood,
the fixed-plane lighting approximation crosses steep outer-boundary triangles:
zone8's conservative full-sway probe reaches 0.411 m error. A diagnostic using
the shader's actual vertex amplitude reaches 0.178 m. The largest sampled
attenuation error is 0.0149 (about 1.5 percentage points, at another vertex).
The receipt records both cases. Original water levels in the sampled cases are
flat and have zero measured sway-plane error. This is mean-plane lighting,
not dynamic wave lighting or a complete sloped-water solution.

Final application/runtime evidence is in `cover-coasts-probe/export.json`:
all 232 production scripts match the tested pack, SHA-256
`65da01d177ddfa7dc50eaa24e81b6243e670d4677a2d55f99adc41dd2c715672`.
It uses the prior patched runtime `090f2254527771465e745bb887386978dfca069ef1943b3b9bcadcad1a377a44`
and unchanged native library. No template, installed build, original asset or
save changed. Continue broader biome/atlas profiles, shared weather wind and
actual submission LOD; U45 remains first on the later gameplay track.

### V2: verified atlas families for cover placement

Follow-up to `5a50b5f`, 9 October. Optional cover now uses original atlas-family
metadata to thin flowers/dry tufts toward soil, rock and paving corners, and
to admit beach debris on eligible ground whose actual atlas slot contains a
sand family. It still requires the verified sea habitats and existing dry,
slope, footprint and scenery checks. No default, shader, wind, sea identity,
breaking-surf or gameplay rule changed.

Reference R1 `0092dc6e1d7c4aab3f74644a79e9bfca11ecf293` entry points:
`Source/terrain_tile_presets.h:3–9` documents editor `af24d45` provenance and
NW/NE/SE/SW signatures, with preview top at smaller original atlas V.
`Source/terrain_tile_blend.h:146–190` maps rotation, sand slots and bare corners.
`Source/renderer_ground_cover.cpp:197–225,500–508,2044–2062` consumes those
families, interpolates bare share and thins cover along grass/road transitions.
Our existing seeded placement provides the variation; no new reference noise
field or random stream is introduced. Fully bare art suppresses meadow/dry
tufts rather than retaining the reference's small residual density.

Implementation map:

- `tools/benchmarks/biome_cover_metadata.py` reads pinned reference metadata
  and an original-atlas fingerprint census. It generates only semantic masks,
  with no original texture bytes. The reproducible command is in the receipt.
- `game/src/game/fx/biome_cover_tiles.gd` recognizes 196 distinct original
  512×512 RGBA8 images across 38 metadata profiles / 259 atlas references.
  Each slot byte holds bare corners in bits 0–3 and sand corners in bits 4–7.
  There are 10,044 classified slots. Modified/unknown textures or unsupported
  dimensions retain the earlier ground-type rules; there is no guessed match.
- Four slots have conflicting labels for identical pixels in `bz3g` versus
  `zone9`: atlas 4 slot 19, atlas 5 slot 7, atlas 7 slots 8 and 28. The generator
  leaves each entire disputed slot neutral. This was caught by its initial
  consistency assertion; do not silently select whichever profile loads first.
- `game/src/game/fx/biome_cover.gd` publishes masks with its immutable snapshot.
  `bare_share` uses the actual sampled triangle UV, including rotation/jitter,
  reverses decoded-image V once, removes the original 8-pixel tile gutter and
  interpolates the corners. `weights` thins ground types 0/5/11 with
  `1-smoothstep(.30,.75,bare_share)`; flower footprints also reject strongly bare
  edges. `beach_sand`, `bank_weights` and `footprint` use the sand-family rule.
  Mound soft-sand identity, snow straw, sand tufts and litter remain separate.
- `tools/tests/biome_cover_families.gd` checks explicit rotated-corner oracles,
  altered/unknown images, disputed slots and native/script authored deltas.
  `tools/tests/biome_cover_families_render.gd` loads complete scenery and
  compares identical scenes with family masks disabled/enabled/restored. Its
  fixture chooses a camera with actual terrain/scenery clearance.

See [biome-cover-families-2026-10-09.json](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/validation/biome-cover-families-2026-10-09.json)
for all commands, hashes, images and the retained failure. **44,102 assertions
pass in ten final runs**, including base/Lost in Astral regressions and three
desktop renderers. Native/script scans of six actual maps agree exactly:
131 flowers/tufts are omitted, four shells are added, and all 15,619 surviving
records keep their values and hashes. These counts omit scenery exclusions;
they are not counts of visible gameplay objects.

The full-scene visual comparisons confirm local flower counts 10→7 at a rock
transition and shells 13→14 at a sandy edge. The first shell camera was inside
a cliff and correctly failed the visibility assertion; its evidence remains
in `cover-families-views-gl`. Clear opposite-side views pass on Compatibility,
Mobile and Forward+, with exact restoration on each renderer. These before
images disable only the family masks in the same candidate pack, making the
placement difference explicit. Existing mixed meadow and isolated shell tests
also pass pressure, pause, shadow refresh, snapshot release, rebuild and exact
option-off restoration. This is scoped visual acceptance, not a complete
mixed-biome or device assessment.

Eight-atlas sample maps retain 512 bytes of mask payload, excluding containers.
Fingerprinting occurs during optional snapshot preparation; no new per-frame
work, shader sampler or GPU upload is added. This is a placement improvement,
not a demonstrated FPS gain. Custom per-map `ei_atlas_profile` metadata and
the reference's remaining cave/Dead City cover sets are not imported.

Final pack: `.../v2-vegetation/cover-families-probe`, SHA-256
`816c8045e87b813fc4a36476618dffa98b7d84fb2f371cbd949ca89f50be9710`;
all 233 production scripts match its manifest. The prior patched runtime and
native library are unchanged. Cover stays off by default; the earlier coastal
flood-lighting and Mobile mound-restoration limits remain open. Continue shared
weather wind, actual submission LOD and remaining regional sets, then the rest
of the renderer handoff and gameplay U45 first.

## V2 shared vegetation weather wind — 9 October

Trees, grass and optional biome cover now sample one terrain-owned wind state.
The existing `gfx_wind` switch controls it; no new effect default is enabled.
This also fixes foliage continuing to sway during a scene-tree pause. The
original water vertices, precipitation trajectories, weather events and random
simulation are unchanged. Desktop sun aiming remains continuous on every
backend; this change does not alter the Android/web held-sun fallback.

Reference source is **R1 `0092dc6e1d7c4aab3f74644a79e9bfca11ecf293`**, inspected
without changing the R0 reference checkout:

| Reference location at R1 | Applied idea |
|---|---|
| `Source/weather_wind.h:87–128`, `update_weather_wind:130–182` | Deterministic smooth spells, force floor, saturating storm strength and slow direction wander. |
| `Source/ground_cover.h:435–449`, `sway_drive` | Stronger weather bends farther; travelling phase rate stays constant at 0.6375 radians per game second. Multiplying elapsed time by changing speed would race the phase. |
| `Source/ground_cover_interaction.h:23–35`, `gcWindSway` | Broad fronts shared in world space. The remake uses two broad harmonics; trees retain separate leaf flutter. |
| `Source/renderer_ground_cover.cpp:2391–2399` | Cover consumes the same environment as foliage. |

Read these with `git -C /home/llm2x/Documents/evil-islands-owned-renderer show
0092dc6e1d7c4aab3f74644a79e9bfca11ecf293:Source/weather_wind.h` (substitute the
other source paths). These R1 files need not exist in the working R0 tree.

Implementation map:

- [weather_wind.gd](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/game/src/game/fx/weather_wind.gd:1)
  owns the pure sampler and shared shader function. Its 32-bit hash multiplication
  avoids signed 64-bit overflow. Map-name seeds keep a map stable without tying
  the noise seed to a changing force. The existing client cosine precipitation
  fade supplies rain/snow; snow contributes 80% storm strength and caves ignore
  precipitation and reduce sway to 20%. This deliberately adapts the reference's
  longer fog/weather ramp. The reference's separate pulse/wisp integration is
  not imported. Each phase is wrapped independently, avoiding an hourly jump.
- [terrain.gd](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/game/src/ei/terrain.gd:1420)
  caches one sample per terrain-clock/owner state. Original water wind supplies
  direction/force read-only; EI horizontal coordinates are converted to Godot XZ.
  The normal World → Map → Terrain ownership resolves the current client's
  weather. Held terrain time also holds its sampled weather, even if GameSound
  continues processing under an ALWAYS parent. Hidden, non-current and server-only
  worlds cannot publish foliage globals. A held arrival can publish its initial
  state without advancing the clock.
- [gfx.gd](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/game/src/game/gfx.gd:613)
  registers two shared vec4 uniforms. Terrain supplies those to
  [figure.gd](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/game/src/ei/figure.gd:30).
  Trees retain root/part height, cactus stiffness and the wind-off/rigid shader
  specialization. `TIME * 0.0` remains only in animated vertex paths so Godot
  invalidates local caster shadows even though visible motion uses game time.
- [terrain_details.gd](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/game/src/game/fx/terrain_details.gd:20)
  and [biome_cover_mesh.gd](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/game/src/game/fx/biome_cover_mesh.gd:39)
  bind the same state to grass and cover. World-space sway is transformed back
  into each model's coordinates. Grass/cover displacement is bounded by 4 cm
  before tip/fade weighting, retaining the existing submerged-cover admission
  allowance. Rigid litter's zero tip weight remains fixed. Underwater mean-depth
  lighting still runs after the actual deformation.
- [game.gd](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/game/src/game/game.gd:666)
  publishes the incoming world's state after attaching its sound/weather owner.
  [menu_scene.gd](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/game/src/ui/menu_scene.gd:58)
  does likewise before its first rendered frame. Terrain `apply_gfx` also publishes
  current wind when the option is enabled while paused.

Validation is recorded in
[weather-wind-2026-10-09.json](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/validation/weather-wind-2026-10-09.json).
Thirteen accepted runs pass **298,141 assertions**. Two additional candidate
runs retain one failed exact-restoration assertion each; they are not counted
as fully passing runs. All artifacts, frozen tools and logs live under
`.../owned-renderer-improvements-20261008-qa/v2-vegetation/cover-wind-*`.

- [weather_wind.gd test](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/tools/tests/weather_wind.gd:1)
  checks independent unsigned-hash oracles, 1,000 deterministic weather samples,
  the analytical displacement bound, rain/snow fade endpoints, frame partition,
  phase wrap/hour/day continuity, ownership, paused option changes, menu entry,
  LMP holds and speed scaling. A canvas shader reads the actual uploaded globals;
  exported `global_shader_parameter_get` is editor-only and cannot be used here.
  A real multipart `nafltr56` tree verifies motion, exact held images and shadow
  refresh on Compatibility, desktop Mobile and Forward+.
- The unchanged previous pack reproduces continued tree motion with
  `SceneTree.paused=true`, `Engine.time_scale=1`: 18,414 pixels change in its
  paired held captures. The candidate changes zero. Setting time_scale to zero
  also freezes Godot shader TIME, so the earlier zero-scale controls are expressly
  discarded as a reproduction of scene-tree pause.
- Updated [foliage_shadow_cache.gd](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/tools/tests/foliage_shadow_cache.gd:1)
  passes 141 assertions on each backend across all seven base/fade/contact/rigid
  cases. Inactive cases submit zero shadow primitives; active cases submit 14
  and visibly move. All four wind-disabled control captures match the previous
  pack byte for byte on desktop Mobile.
- Grass/cover pressure, real meadow, kelp, Gipat zone7 beach shells, rigid litter,
  pause and option restoration are exercised. The underwater zone8 test probes
  eight directions at the full 4 cm radius, retains authored water coverage,
  passes 4,096 real GPU depth samples, and detects all 1,024 deliberately wrong
  bindings. Native placement records are unchanged by the wind implementation.

Limits to carry forward:

1. A full real-tree wind/reset round trip on desktop Mobile changes **922 pixels,
   38 over 2/255, peak 7/255**; each held image itself is exact. A controlled-clock
   version of the original foliage shader on the previous pack has a similar
   residual (**880 pixels, 40 over 2/255, peak 7/255**). That comparison uses different
   wind geometry and does not prove pixel identity or fix the underlying renderer
   behavior. Removing scene-instance recreation does not remove it. Wind-disabled
   transforms restore exactly in both packs. Keep full Mobile exact-restoration
   acceptance open.
2. The combined grass/cover Compatibility rebuild changes one pixel at (433,70),
   from RGB (25,16,8) to (22,17,12). The unchanged previous pack reproduces the
   exact same pixel and values. Cover-only Compatibility and combined Forward+
   restoration are exact. Preserve the failing combined fixture and its control.
3. On zone8 flooded by +0.65 m, the existing outer-map mean-plane approximation
   has a conservative all-direction error of **0.469438 m** at full 4 cm sway.
   That worst point is a fixed root. With actual vertex tip weights, the maximum
   envelope error is **0.206243 m**; the largest attenuation error, **0.02104365**,
   occurs at a different vertex. These probe the displacement envelope rather
   than a specific weather/time state. Sampled flat water has zero error. Do not
   label this dynamic-wave lighting or claim the earlier boundary limit is fixed.
4. These are desktop correctness tests. No Android/web timing, battery or FPS
   gain is established. The extra shared CPU sampling and second broad grass
   harmonic have not received device performance acceptance. Other user Godot
   processes were left alone; their PIDs are recorded. The original weather,
   water geometry and precipitation simulation remain intact. Global light/wind
   ownership still assumes one current main view, as the existing renderer does.

Final pack: `.../v2-vegetation/cover-wind-final`, SHA-256
`cef82e76da9e113687413b963cd969b0b9cf5ce869fbc86f4f509628afdd04f5`.
All **234** production scripts match its export manifest. It uses the previously
validated Mobile and Forward+ engine patches; no new engine patch was added.
The pack is a QA artifact, not an installed or published release. Continue
**actual geometry submission LOD**, remaining regional cover sets, then the
rest of the renderer handoff and gameplay **U45 first**. Shared wind for fog,
clouds and ambient particles belongs to their later visual work.

### V2 investigation notes recorded before implementation

These notes describe the clean shared-wind checkpoint `6c665f8`. The following
implementation section supersedes their pending status. They explain why
fully faded chunk removal and native cover geometry LOD were selected.

- `terrain_details.gd:_stream` retains up to 80 chunks in a five-chunk radius.
  `_chunk_mesh` already swaps grass near/far blade meshes at 18 m, and
  `blade_mesh` already installs screen-space index LODs. Preserve that existing
  grass LOD; it is not a missing feature to implement again.
- `biome_cover_mesh.gd:SHADER` currently collapses geometry over 28–36 m and
  thins seeds above 0.35 over 18–28 m, but all cover indices are still submitted.
  `biome_mounds.gd:VERTEX` lowers mounds over 24–32 m and the fragment shader
  discards the buried result. `_install_chunk` creates one grass MultiMesh
  parent with `BiomeCover` and `BiomeMounds` mesh children.
- A conservative first candidate can suppress the grass/cover parent once
  every possible root in its 8 m chunk is beyond the 36 m fade end, and suppress
  the mound child beyond 32 m. Use distance to the entire root rectangle, not
  its center. Whole-chunk bounds avoid scanning every native grass transform
  again on the main thread. Validate movement within a chunk, chunk edges,
  teleport, exact reappearance, shadows, streaming completion, water/option
  rebuilds and cleanup. Visibility of a parent must not hide a still-visible
  mound child accidentally.
- Match the actual shader coordinate contract: grass/cover root distances use
  `MODEL_MATRIX` world XZ; mound `CUSTOM1.xy` currently stores its own XZ center.
  Handle transforms conservatively, with a fallback for tilted terrain if
  relying only on XZ chunk bounds. A small conservative margin can permit
  skipping repeated culling work for sub-centimeter camera movement.
- This would remove genuinely invisible submissions without extra near draw
  calls or duplicated vertex buffers. It does not by itself implement the
  reference's survivor compaction or simpler intermediate cover geometry.
  Do not use automatic screen-space density LOD if it can drop cover before
  the current shader has faded it; material focus and renderer camera distance
  are different quantities. Measure main-thread maintenance cost as well as
  visible/shadow primitive and draw reductions before accepting a net gain.
- Reference R1 `Source/ground_cover_interaction.h:6–22` separates density from
  projected-leaf far-mesh choice; `Source/renderer_ground_cover.cpp:584–595`
  chooses far meshes and `:2658` uses indexed indirect draws. Those decisions
  need an explicit Godot adaptation, not a direct shader-only port.

## V2 native cover LOD and faded submission culling — 9 October

Implemented after `6c665f8` in the canonical checkout. This is a local,
unpublished checkpoint. Grass/cover remain controlled by their existing
options; `gfx_biome_cover` is still off by default. No new engine patch,
installed template, original asset, save, device installation or protocol
change. Desktop sun aiming remains continuous on every backend; the held
Android/web fallback is unchanged.

### Reference and implementation map

The inspected reference is R1 `0092dc6e1d7c4aab3f74644a79e9bfca11ecf293`:

- `Source/ground_cover_interaction.h:6–22` separates distance-density thinning
  from projected leaf size and far-mesh selection.
- `Source/renderer_ground_cover.cpp:584–595` selects its simplified tuft meshes;
  `:2658` issues indexed indirect draws. The reference also grows thinning
  survivors and uses fewer, wider leaves. Those parts are **not** implemented
  by this adaptation.
- The existing Godot grass implementation already has near/far blade meshes
  and native index LODs. Its layout, placement and LOD policy are unchanged.
  Godot's selector was inspected in the pinned runtime source under
  `p5-shadow-cache/engine-mobile-lock/drivers/gles3/storage/mesh_storage.h:386`
  and `servers/rendering/renderer_rd/storage_rd/mesh_storage.h:480`.

The production changes are confined to these owners:

| File / symbol | Result and constraints |
|---|---|
| `game/src/game/fx/biome_cover_mesh.gd:154`, `bent_ribbon` | Joins the original end vertices of two curve segments: four triangles become two. Applied to dry tufts, reed leaves, dead bushes, wrack and the upper two sea-grass segments. It keeps every plant. |
| Same file `:166`, `leaf`; `:210`, `shell` | Raised leaf diamonds use two far triangles instead of four; each shell ridge fan uses one instead of three. Needles, twigs, stones, stems, flower heads and cattail heads keep their existing faces. |
| Same file `:237/301`, `build` / `lods` | Near arrays remain exact, including normals, colours, stable density seeds, root coordinates, ground anchors and per-vertex mean-water planes. The far mesh uses another index buffer into those vertices. The maximum per-chunk curve/detail size selects the native LOD; it is a visual heuristic, not a formal bound on shaded-pixel error. |
| `game/src/game/fx/biome_cover.gd:463`, `build` | Publishes the LOD dictionary with the existing immutable chunk data. Worker ownership, placement RNG and mound generation stay unchanged. |
| `game/src/game/fx/terrain_details.gd:656`, `_install_chunk` | Installs the cover's native index LOD. When interaction is enabled, `lod_bias = 4` delays simplification of bent silhouettes. Mounds retain their original dense topology. |
| Same file `:719/725`, `_root_bounds` / `_cache_root_bounds` | Caches the complete 8 m root rectangle, including upright rotation/scale/translation. Tilted terrain retains its plants conservatively because root height can affect world XZ. Mound bounds use the shader's existing untransformed `CUSTOM1.xy` contract. |
| Same file `:733/757`, `_cull_chunk` / `_update_submissions` | Suppresses plants only beyond their 36 m fade and mounds beyond 32 m, with a 10 cm hide margin. A parent needed by a mound stays visible while its faded grass instance count becomes zero. It avoids repeated visibility/instance-count writes. |

Culling follows the material's ground focus, not camera-eye distance or the
chunk center. A cached travel allowance permits at most 50 cm between scans,
reduced by the closest hidden bound's distance to its live fade, retaining a
5 cm safety margin. Distance to a rectangle changes by no more than camera
travel. Delaying a hide submits extra already-faded work; entering a live fade
must trigger a scan. New worker installs use the **latest** material focus,
not the older scan focus, and invalidate the scan cache. Transform changes,
water/option clears and world teardown are handled explicitly.

Diagnostic controls are `--ei-no-cover-lod` and
`--ei-no-vegetation-culling`. They do not add player-facing options. The timing
fixture skips the new maintenance call in its baseline phase so that the
control does not pay the culling scan it is meant to compare.

### Accepted evidence and visible differences

[Machine-readable receipt](validation/vegetation-submission-2026-10-09.json)
contains the frozen tools, commands, source/pack/runtime hashes, measurements,
failed controls and image hashes. Ten accepted runs pass **132,854 assertions**.
A separate Compatibility whole-scene run retains **four failed exact-image
assertions** and is not counted as fully passing.

- `tools/tests/vegetation_submission.gd` compares against the frozen geometry
  source from `6c665f8`, checks all 14 kinds, forbids triangles crossing plant
  roots/seeds/anchors, and verifies every plant survives. It checks transformed
  bounds, accumulated small movement, teleport/reappearance and new installs
  during a skipped scan. Authored dry and sea arrays also match the old source.
- Native and `--ei-script-grass` cover/worker regressions pass. The existing
  species-filtered render tools now regenerate LODs whenever they filter and
  rebuild arrays; retaining pre-filter indices would be invalid.
- Full authored meadow culling is pixel-exact on Forward+ and desktop Mobile,
  including separate render-thread execution. The Compatibility terrain and
  vegetation control, with authored scenery hidden **after placement**, is
  exact for all five focus positions. Placement exclusions remain in use.
- All three backends restore their original full-detail captures exactly after
  the automatic LOD comparison. The near meadow capture changes 0 pixels on
  Forward+/Mobile and 2 on Compatibility; middle changes 6–8; wide changes
  48–81 at 800×600, with peaks up to 39/255. These are intended geometry/lighting
  differences, not a claim of identical distant rendering.
- Interaction keeps the sampled near/middle/wide images exact relative to full
  detail; the delayed LOD consequently saves very little geometry there.
- The authored kelp scene is exact near, changes 39 middle pixels (peak 5/255)
  and 2,004 wide pixels (peak 24/255). Its wide view reduces visible primitives
  from 81,338 to 74,398 and shadow primitives from 103,859 to 94,435. Screenshots
  were inspected; the prior shoreline mean-depth approximation remains open.
- `tools/tests/biome_mounds.gd --mound-submissions` passes all **56** Forward+
  checks. Its four culling image comparisons are exact; far mounds submit no
  draws, near mounds return, and the existing footprint/ground-height,
  exposed-trough, pause and restoration checks pass. The headless mound oracle
  also passes. This does not resolve the older Mobile restoration limitation.

The Compatibility differences are exactly five distant scenery pixels, with
up to five changing in one comparison. `cover-cull-order-old3` uses the
**unchanged** `cover-wind-final` application pack and native visibility calls.
Its 13 focus positions reproduce **all five pixel coordinates and exact RGB
pairs**. The isolated terrain/vegetation captures remain exact. This is
consistent with pre-existing scenery draw-order sensitivity, not a demonstrated
vegetation disappearance; the native renderer cause is not fixed here. Preserve
that qualification when reporting or extending the work.

### Removed work, costs and limits

| Sample | Full / simplified indices | Reduction |
|---|---:|---:|
| Three plants of every kind | 2,250 / 1,422 | 36.8% |
| Eligible meshes in the 80-chunk meadow | 12,477 / 9,711 | 22.2% |
| Eligible meshes in the 55-chunk sea sample | 120,030 / 79,668 | 33.6% |

These are index counts for affected meshes, not whole-scene speedups. The wide
meadow view removes 800 visible and 1,332 shadow primitives from the full-detail
control. Far indices require four extra bytes each in the builder: about
38 KiB for that meadow sample and 311 KiB for the sea sample; vertices are
shared. Paired geometry construction medians were about 150–164 µs before and
160–177 µs after for meadow chunks, and 4.195 / 4.470 ms for the sea sample.
Generation remains background work where threads are available.

Culling removes 2–15 visible draws in three local ground-focus positions.
Teleporting away from retained chunks removes 142 RD / 160 Compatibility draws;
normal streaming separately retires those chunks, so those larger numbers are
not a steady-state optimization claim. The first implementation scanned 80
chunks in about 80 µs. Cached bounds reduced that to about 34 µs; the final
travel cache runs 48 scans across 240 small moves, averaging about **8.7 µs per
update** in the immediate loop. Its stationary median is below the microsecond
timer resolution. The separate rendered-loop mean is approximately 17–23 µs.

Viewport CPU/GPU timing is noisy and mixed. Other Godot processes were present,
and the short three-mode samples do not establish a net FPS improvement. No
Android/web, battery or thermal benefit is claimed. The Mobile backend was
run on the desktop RTX 3090. Existing default-off visual effects remain off.

The initial probe omitted an explicit Vector3 type; the first baseline control
mixed indentation; one mound invocation omitted its required oracle. Later
tests still expected a hide after 12 cm despite the new conservative travel
cache; they now move beyond its allowance before asserting removal. The new
mound subtest initially restored litter that the older fixture manually hides;
it now reapplies that fixture mask before the original deformation checks.
These failed invocations are retained in the receipt, not counted as passes.

### Reproduction and continuation

Final QA build:
`/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa/v2-vegetation/cover-lod-final3`.
All **234 production GDScript hashes** match its export. Pack SHA-256:
`a7e1ea0d0c838bf1be4ff9ddda809cbc8b2de9b14991a4f653d155e0b18c33a5`.
It reuses the already validated eight-patch runtime/native library; no runtime
changes were made. The six unrelated export-generated UIDs were archived and
removed; committed wind/biome UID files remain.

Use the receipt's exact commands and isolated XDG directories. The runner
freezes the external tool and its relative superclass; also retain the frozen
`cover-geometry-before-lod.gd` and `submission-mound-oracle.gd` specified in the
commands. GPU runs are serialized, offscreen, bounded to 150 seconds and do not
stop unrelated processes.

**Remaining V2 work:** intermediate-range density thinning still submits its
collapsed plants; there is no GPU survivor compaction. This implementation also
does not widen far leaves or enlarge thinning survivors like the reference.
The regional cave/Dead City checkpoint below now follows this submission work.
Continue other renderer opportunities in the established order. Device/long-route
acceptance and the older depth/restoration limits remain. The full goal also
includes the gameplay handoff, starting with **U45**, after renderer work.

## V2 regional cave and Dead City cover — 9 October

This checkpoint extends the existing default-off `gfx_biome_cover` option. It
adds cave habitats and base-game Dead City rules without creating another
streamer, gameplay object or light. It does not enable cover, change the desktop
continuous-sun policy, install a build or publish a release. The source remains
protocol 13 / Experimental 6. The full renderer/gameplay goal is still active;
U45 remains the first gameplay issue after renderer work.

### Reference and campaign evidence

Use reference R1 `0092dc6e1d7c4aab3f74644a79e9bfca11ecf293`, via `git show` in
`/home/llm2x/Documents/evil-islands-owned-renderer`; the checked-out R0 lacks
these later files. Do not switch or modify the reference checkout.

| Reference location at R1 | Adapted behavior |
|---|---|
| `Source/ambient_particles.h:88–96`, `classify_zone` | Cave/outdoor/Dead City context. The reference's bare `zone9` test is insufficient for this remake: base `gz9g` is `gipat`, while LiA `gz9g` is `gipat2`, with different map dimensions, units and scenery. The remake requires base `gipat` + `zone9`, after checking the cave sky. Ambiguous ownerless maps remain conservative. |
| `Source/ground_cover.h:240–373` | Dry/bare Dead City tufts, yellow litter near non-conifer wood including bare crowns, more but smaller dead bushes; cave lava, damp, rock, wall/corner and undead habitats, plus cave snow. Densities/scales are adapted to the existing bounded remake generator. |
| `Source/renderer_ground_cover.cpp:240`, `gcCaveWall`, and damp-field construction around line 530 | Eight directions/four radii probe actual terrain and solid scenery; perpendicular contacts identify corners. Water, dark wall pockets and green original art contribute dampness. Nearby lava suppresses it. |
| `Source/renderer_ground_cover.cpp:1428–1470`, `ground_cover_trees` | A 20 m affinity around original MOB undead unit records. These are decorative authored sites, never live combat/death/fog state. |
| `Source/ground_cover_cave.h`, `cave_undead_site` and shape emitters | Sixteen regional shapes: ash, scoria, obsidian, crust, moss, lichen, ferns, roots, mushrooms, damp stains, slabs, rubble, bones, skulls, webs and crystals. |
| `Source/renderer_ground_cover.cpp:931–935`, and line 994 | Native ground-art contribution for stone/patch materials, dark wet patches, and dim green mushroom emission without point lights. |

The read-only inventories and probe scripts are under
`/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa/v2-vegetation`.
`regional-inventory-base` records all declared base caves and Dead City.
`regional-inventory-astral-clean` records LiA cave owners separately and explicitly
marks the declared-but-missing `zone17.mpr`; its earlier inventory run attempted
that missing map and is retained as an unsuccessful control. Do not manufacture
assets or infer that same-named campaign maps are the same location.

### Implementation map

| Remake file / entry point | Responsibility |
|---|---|
| `game/src/game/fx/biome_cover_regions.gd`, `configure`, `wall`, `habitat`, `weights`, `records` | New immutable habitat snapshot: actual authored liquid mesh centres/material emission, unexpanded placed-scenery bounds, original MOB sites and an independent regional RNG stream. No scene reads in jobs and no strong back-reference to the cover owner. |
| `game/src/game/fx/biome_cover_region_mesh.gd`, `emit` and primitive helpers | New opaque low-poly regional shapes using the existing geometry builder, root anchors, culling and native lighting. Ferns bend; rigid debris stays fixed. No collision, picking, navigation or replicated actors. |
| `game/src/game/fx/biome_cover.gd`, `region`, `weights`, `records`, `build` | Campaign-aware Dead City classification; yellow leaves exclude conifers, dead bushes are one-third size, dry tufts can occupy bare soil. Append regional records after the original dry/bank/sea streams. |
| `game/src/game/fx/biome_cover_mesh.gd`, regional shader branch, `triangle`, `build` | Cave-only CUSTOM2 attributes hold original terrain UV/layer/material. Reuse the terrain's original or resident HD atlas, preserving padded-tile coordinates. Patches blend toward ground art at their opaque rims; mushrooms use the existing native material-emission term. Ordinary cover shader/buffer paths remain unchanged. |
| `game/src/game/fx/terrain_details.gd`, `_index_scenery_box`, `prepare_grass`, `_apply_grass_material` | Capture original solid bounds only when cover is enabled, pass the snapshot to existing workers, and bind the cave atlas variant. No extra scenery record field when cover is off. Existing option/revision barriers own invalidation. |
| `game/src/game/fx/biome_mounds.gd`, `configure`, `records` | Cave snow types 9/12 reuse dense original-triangle geometry and shared compaction; cave sand stays excluded. A separate 1 m candidate lattice at 0.04 candidates/m² finds small snow pockets. Original outdoor seeds/positions and the two-pile/4,096-vertex cap are preserved. |
| `tools/tests/biome_cover_regions.gd` | Habitat rules, finite geometry and envelope checks at flat/limiting slopes, campaign identity, native/script agreement, immutable workers, authored scans and the inherited render/lifetime fixture. |
| `tools/tests/biome_cover.gd` | Regional-aware isolated geometry and shader controls, fern pressure, mushroom emission negative control. The original meadow tests remain available. |

Lava is classified from the liquid layer and material emission, rather than
from ground beneath an overlay. The initial 1.2 m bank-height gate excluded
all lava decoration on the sampled walkable ledges. A read-only scan found
these ledges about 1.5–3 m above lava, with other platforms 7–16 m above it.
The final lava band admits up to 3 m vertical separation; damp water banks
retain 1.2 m. The horizontal field remains an approximation from authored
2 m liquid centres, not an exact signed shoreline or collision query.

New rigid shapes use conservative radii including slope tilt. Admission retains
the dry, low-slope, scenery, supporting-plane and unique root-anchor gates,
with additional eight-direction dry/UV checks. Ground-art primitives must stay
within one compatible source code/UV interval. Large patch/web edges also check
unexpanded solid scenery. These small rigid surfaces follow their root, not
every point of a footprint trench; the older litter-edge limitation still
applies. Snow piles continue to use the denser, conforming geometry.

### Validation and costs

The machine-readable receipt is
`docs/validation/biome-cover-regions-2026-10-09.json`; it contains the precise
accepted-run list, frozen scripts, source/pack/runtime hashes, images, earlier
failed controls and commands. The final export is `cover-regional-final` under
the QA directory. It uses the same eight-patch runtime/native library as the
previous accepted checkpoints; release templates and installed builds stay
unchanged. `prototype3` is a passing validation build retained in the receipt;
its only production difference from final is that final omits the extra solid
AABB field when cover is disabled. Final tests check both branches explicitly.

**Sixteen accepted runs pass 59,182 assertions.** All 236 production GDScript
source hashes match the final export.

The frozen old/current oracle matches **3,247 prior cover records**, their mesh
arrays and native LOD indices, plus sampled outdoor mound meshes, over six maps.
Base and LiA scans validate cave habitats, base Dead City and the separate LiA
zone9. Original-unit sites admit bones/skulls in LiA `gz7d1`/`gz36j`; the ordinary
LiA zone9 receives no Dead City policy. Native and script samplers agree in the
sampled jobs, and jobs preserve their frozen data after original water and MOB
records are mutated in the fixture.

Authored-scene captures cover Compatibility moss/Dead City leaves, Forward+
ferns/lava crust, desktop Mobile mushrooms/LiA bones, and Mobile HD moss. Settled
pause, empty pressure, shadow refresh, clear/reload and off-state restoration
are exact in those accepted runs. The mushroom emission negative control
changes 20 visible pixels (peak 24/255); restoring emission restores the exact
image, with no new light. These are controlled scene checks, not full-game
visual acceptance or Android measurements.

Base `gz14k` contains 572 cells of actual snow; 465 tested cell centres are dry
and low-slope, but only 56 admit the probe's normal-size full footprint. The
old outdoor candidate lattice found no cave piles. The independent cave stream
finds two in the metadata scan. A real placed-scenery Forward+ fixture selects
one at `(28.45712,43.57837)`: 601 vertices / 929 triangles, zero UV error,
original-height error below 0.6 micrometres, and exact whole-scene option/rebuild
restoration. Fully compacted snow exposes 182 exact underlying trench pixels.
The same fixture checks the existing shared deformation, queue/worker lifecycle
and separate render thread.

There is a cost: caves store another 16 bytes per cover vertex, plus bounded
snapshot buckets for liquids, walls and authored sites. The new shapes add
geometry and shadow work. Sample native record-generation medians are roughly
1.5–6.5 ms per tested cave chunk, with maxima around 9.5 ms; source-data-only
scans omit placed scenery and are not total build/upload/frame measurements.
The script fallback is slower. A 25-chunk snow fixture finds one active chunk:
its sampled mesh build costs about 8.8 ms, versus 52 microseconds median across
all 25 mostly empty chunks. Other render processes may exist; do not turn these
construction samples into an FPS claim. Cover stays off on all platforms.

Earlier controls remain in the receipt: an overly strict normal-length fixture
mistook scaled normals for degenerate triangles; the fern's small root ribbon
is valid inside the existing 8 mm root offset; coarse lava sampling missed the
only crust pocket; and the initial cave mound lattice missed small snow patches.
A NUL literal used in an early name check emitted Unicode diagnostics and was
replaced by code-point validation. None of those early runs is counted as a
fully accepted final checkpoint.

The regional categories are implemented; long gameplay routes, full visual
review, device generation/upload/overdraw costs, survivor compaction and the
older coastal depth and Mobile restoration limits remain open. Other reference
shape variants are not asserted to have one-to-one parity. Continue the
remaining renderer list, including V4 wave fields and waterfall detail,
then the gameplay handoff starting with U45. Do not enable defaults on the basis
of these isolated tests.

## V4 river currents — final checkpoint, 9 October

**Implemented in `eda826d`.** **River currents** (`gfx_water_current`) defaults
off on every platform and requires Water and lava effects. Visible sloping
water receives downstream normal motion. With Water contact and wakes enabled,
stationary/wading creatures also produce a short downstream foam streak.
This is a surface shading effect, not a propagating wave or persistent trail.

### Implementation map

| File in the canonical checkout | Role |
|---|---|
| `game/src/game/fx/water_current.gd:38` | Snapshot the existing authored water meshes. Recover each two-metre tile origin before mapping its grid vertices: individual vertex XY jitter can exceed half a metre. Reject inconsistent/mixed copies, buried overlays, type-4 shores, swamp/lava/emissive surfaces and verified sea materials. Ground height only determines burial; water height determines flow. |
| `game/src/game/fx/water_current.gd:77` | Reuse unchanged fields; main-thread texture upload; one worker plus the latest request on the script fallback. Pending work is joined on disable/retirement. Completed fallback fields can lag continuously changing flood levels by a build. |
| `game/src/game/fx/water_current.gd:134` | Scalar mean-height differences, 5×5 tent smoothing, bend and bounded velocity. `sample` at line 192 exposes the same clamped grid field for future wave advection. This does not replace the exact deformed triangle query in `water_surface.gd`. |
| `game/src/native/source/water_current.h` and `nav_kernel.cpp` | Optional `WaterCurrentKernel`, same packed-array result. No scene or navigation ownership. Rebuilt Linux library is checked in; existing Windows/Android libraries automatically use the script fallback until rebuilt. |
| `game/src/game/fx/water_current_shader.gd` | Explicit four-tap vertex interpolation; two cross-faded 0.9-second advection phases, bend-limited displacement and derivative footprint. No cumulative `flow * time` stretching. |
| `game/src/game/fx/water_interaction_shader.gd` | Combined variant adds bounded downstream foam and slope-aware height rejection. Keeps the original moving-wake reach; a larger culling envelope is only for the current tail. |
| `game/src/ei/terrain.gd` | `apply_gfx`, `set_rain_cover`, deferred `_refresh_water_current`, `_process`, `_exit_tree` and `_update_wave_parameters`. One bounded phase uniform uses the existing pausable double terrain clock. Ordinary frames do not rebuild the map field. |
| `game/src/ei/game_data.gd`, `remake_text.gd`, `game/src/game/gfx_detect.gd` | Default-off option, English/Russian/German text, applied-option registration and low-tier preset exclusion. |
| `tools/tests/water_current.gd`, `water_current_render.gd` | Analytic/source rules, base/LiA native-script comparisons, flooding/coalescing/teardown, actual river/level-stream images, clocks and production shader diagnostics. |
| `tools/tests/water_interaction.gd --with-current` | Existing contact/controller, liquid-material, weather/reflection and restoration regression with the combined shader. |

The implementation deliberately omits verified sea profiles: their authored
shore ramps are not a reason to turn breaking surf into river flow. It also
omits contradictory material copies instead of inventing a join across shifted
layers. This is conservative visual coverage, not a hydraulic simulation.

### Reference map for this stage and the next

Read **R1** through `git show 0092dc6e1d7c4aab3f74644a79e9bfca11ecf293:PATH`
in `/home/llm2x/Documents/evil-islands-owned-renderer`. The checked-out R0 tree lacks
some of these later files; do not switch or edit that reference checkout.

- `Source/owned_terrain_front_end.cpp:152–325`: visible liquid height,
  central/one-sided gradients, tent smoothing, bend and additional cascade/pit
  fields. This stage implements current/bend, not the cascade or pit-fill model.
- `Source/shaders/liquid_surface.hlsl`: `liquidRiverPhases`,
  `liquidRiverSlope`, `liquidUnitContact` and the `liquid_surface` current block.
  Bounded advection and smooth bend avoid long-play stretching/triangle seams.
- **Next: propagating field**, `Source/liquid_waves.h` and
  `Source/renderer_liquid.cpp:62–225`. R1 uses a 512² ping-pong field at 0.125 m,
  1/30 s fixed steps, height/previous-height/trail channels, bounded substeps,
  integer window shifts, edge damping, unit pressure and current-advection of
  trails. Its D3D compute implementation needs a Godot/backend adaptation.
  Reuse the existing 16-contact admission and this field's velocity. Verify
  lingering waves after a unit leaves, pause/rewind/teleport, window shifts,
  flooding and teardown. Analytical V wakes are not that simulation.
- **Then waterfalls**, `Source/procedural_falls.h`,
  `Source/renderer_ambient_particles.cpp:299` and
  `Tests/procedural_falls_regression.cpp`. Detect coherent exposed liquid drops,
  reject isolated spikes/buried/border artifacts, build the shell and then add
  bounded lip/impact/mist emitters. Do not classify every slope as a waterfall
  or assume this current field retains all mixed-material lip vertices.
- `Tests/liquid_surface_smoke.cpp` and `Tests/liquid_waves_regression.cpp`
  supply additional reference geometry/clock/pressure expectations.

### Acceptance and practical limits

Receipt: [water-currents-2026-10-09.json](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/validation/water-currents-2026-10-09.json).
**Eight final runs pass 26,315 assertions.** The exported pack has all 238 current
production GDScripts and the new Linux helper. Base zone1/8/15 and LiA
zone1/8/9 fields match the scalar result with **zero measured component error**.
Synthetic coverage includes planar/flat/buried/holey/mixed-level surfaces,
sector-grid continuity, source XY jitter, excluded liquid families and malformed
native dimensions. Fallback flooding coalesces, converges and releases its
snapshot even when disabled with a worker running.

The real zone8 focus is `(160, 12.4863577, -142)` in Godot space. All three
desktop renderers pass clock reset, scene pause, inactive/LMP-held world,
off/restored appearance and empty-contact controls. Zone1's level-stream
control retains exact pixels. Isolated production normal detail is exactly
periodic after ten phases and one hour of game time; phase-wrap comparisons
peak at 1/255. A stationary body gains downstream foam in the river and none
in the level stream. The combined existing water regression passes 75 checks.

The accepted build's initial compiled calculation costs **0.261–5.929 ms** in
these samples; scalar calculations cost **10.063–213.070 ms**. Total initial
preparation includes mesh extraction and costs **18.661–147.438 ms** on native
samples. The largest sampled RGBA32F field is **4,210,704 bytes** (513²), plus
CPU snapshots and transient build/upload storage. These are diagnostic desktop
costs with other processes present, not a controlled FPS, GPU-cost or device
claim. Initial preparation is synchronous. The optional shader adds four
vertex fetches and, on flowing fragments, four extra normal-texture samples.
The fallback worker bounds the queue; it does not prove cheap browser execution.
Actual Android/browser memory, visual and performance acceptance remains open.

A prototype Mobile restore comparison differed at 38 pixels (peak 3/255). It
was not reproduced in the final export or the unchanged-renderer control; its
cause is not established, and that run is excluded from the accepted count.
Earlier fixture/export failures and the corrected coroutine-retention control
are retained in the receipt. The final pack and shader tests pass; do not turn
that scoped result into a guarantee for every map/device or earlier cover issue.

### Reproducible checkpoint

- Export: `/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa/v2-vegetation/current-final`.
- Pack SHA-256: `ae40663739ab74265f6ffc0d76eaff5b3045bd0e6e04d7dceed11b38b67d85d2`.
- Runtime SHA-256: `090f2254527771465e745bb887386978dfca069ef1943b3b9bcadcad1a377a44`.
- Linux helper SHA-256: `dfd05a2ac322886c759d1512d7ca830388a67cbac8e04c529312855ba1eb0b69`.
- Runtime still carries the eight previously accepted common engine patches;
  no new engine/template change was made. Linux helper uses the documented
  clean godot-cpp `507ed9d840c01a3c5b2a39af8bb4000bfac30bf5`.
- QA runner: `/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa/v2-vegetation/run.py`. Always pass `--build=current-final`; its default
  build is historical. Use `tests/water_current.gd gl_compatibility --headless`,
  add `--ei-script-water-current` for fallback, or `--astral --current-astral`
  for LiA. Use `tests/water_current_render.gd` with a desktop renderer and
  `--current-flat` for the level-stream control. Runs use private XDG data,
  an offscreen non-focusing window and a 150-second limit; run GPU checks serially.
- Original assets/reference/save profiles and installed/published builds were
  untouched. Six unrelated export-generated UID sidecars were archived under
  `/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa/v2-vegetation/export-generated-uids-current` and removed from the working tree.
- At handoff there is no task-owned test/worker process to resume. The user
  requested a stop after this checkpoint. The goal remains incomplete; resume
  from the established order below, not from the old isolated branch.

## V4 propagating water field — 9 October follow-up

`gfx_water_waves` adds persistent spreading ripples and stirred-water trails from
currently visible, posed wading creatures. It requires enhanced water and water
contacts, and defaults **off on every platform**. Settings are now separated into
World/textures, Terrain/vegetation, Lighting/shadows, Water, and Weather/effects
(`41d67e0`); the existing 110 controls retained their values and defaults.

### Implementation and ownership

- `game/src/game/fx/water_wave_field.gd`: 128×128 quarter-metre cells over 32 m,
  30 Hz fixed steps, at most eight catch-up steps and 16 current contact sources.
  RGBA32F stores height, previous height, trail and mean surface (256 KiB).
  Pressure propagates without a source; trails follow the existing optional
  current field and expire after 25 quiet game seconds. Borders absorb energy.
- `game/src/native/source/water_wave.h`, registered in `nav_kernel.cpp`: pure
  packed-array Linux solver. The identical scalar fallback owns one worker job,
  immutable snapshots and bounded elapsed time; it cannot grow a work queue.
  Teardown joins the worker, discards its Callable and releases the histories.
- `water_surface.gd` permits an unposed query. The field samples actual authored
  triangles and their gradients through a bounded one-metre cache. Navigation's
  upper-corner water height was metres above the visible zone8 river, so using
  navigation here was rejected. Overlapping window shifts reuse cached samples;
  flood/rewind/teleport clears stale state. Fine shore/material edges remain
  conservative and the shader also rejects incompatible surface heights.
- `water_interaction.gd` supplies admitted contacts and the terrain clock.
  Hidden/leaving actors stop stamping immediately while existing water history
  continues. Pause, travel, movie holds, world switches and disable follow the
  established controller lifetime. Neither actors nor field enter save/network data.
- `water_wave_shader.gd` and the two cached terrain variants add normal gradients
  and faint stirred-water/foam shading in the existing water pass. Current/no-current
  combinations, late rain-cover publication and existing lava/swamp branches are
  covered. This is shading, not displacement of authored water geometry.

Reference: R1 `0092dc6e1d7c4aab3f74644a79e9bfca11ecf293`,
`Source/liquid_waves.h`, `Source/renderer_liquid.cpp`, and
`Tests/liquid_waves_regression.cpp`. The smaller grid is an explicit Godot budget
adaptation; it does not claim parity with the reference's 512² field.

### Validation and limits

[Wave receipt](validation/water-waves-2026-10-09.json): **304 assertions pass in
nine final private exported runs**, covering native/scalar analytical parity,
16 varied sources, source-free propagation/advection/decay, dry and separate-level
boundaries, real base/LiA data, fallback pending-job cleanup, Compatibility,
Forward+ and desktop Mobile. The existing contact regression contributes 75.
Empty/disabled/restored views and held-clock views are exact; active history
leaves lava and swamp exact and adds no water draws. Actual paused/travel/movie/
loading schedules and accelerated time are exercised. The extra real sloping-river
case caught and corrected the navigation-height coverage defect before acceptance.

The effect is intentionally subtle: the river history changes 2,558 pixels at
up to 3/255, while the Forward+ still-water case changes 1,476 at up to 10/255.
These are deterministic paired captures, not visibility or performance guarantees
for every camera. The final fixture also verifies surface height and retained trail.

Cold authored-surface coverage cost **52.945–80.906 ms** in three sampled headless
cases. Sampled solver calls cost **0.663–1.280 ms native** and **42.909 ms scalar**
(on its bounded worker). These are diagnostic call timings, not whole-frame/FPS
comparisons. Cold/flood preparation cost and physical-device bandwidth remain
open. Only the Linux helper was rebuilt; older platform helpers use the scalar
fallback. No platform/default rollout is justified by this checkpoint.

Reproduce with the private `waves/run.py` and `--build=waves-surface-final`:
`tests/water_wave_field.gd gl_compatibility --headless --fresh-cache`, adding
`--ei-script-water-waves` for fallback or `--astral --wave-astral` for LiA.
Use `tests/water_wave_render.gd` with each renderer; add `--with-current --wave-river`
for zone8. Keep GPU runs serial. Sources, exports, tool snapshots, image hashes,
rejected prototypes and exact commands are recorded in the receipt.

## V4: authored waterfall foam, spray and mist — 9 October

Accepted in `4a595dc`; `gfx_waterfalls` defaults off and requires enhanced water.
The detector in `waterfall_field.gd` snapshots actual authored water geometry,
including XY jitter and mixed liquid owners. It admits coherent, exposed,
non-emissive steep drops and rejects shallow rapids, isolated spikes, buried
surfaces, borders, contradictory copies, lava and swamp. The shell reuses the
selected original water triangles and displacement, rather than replacing the
authored flow with a ballistic sheet. `waterfalls.gd` owns at most 32 sites,
24,576 shell vertices and 1,536 fixed spray/mist sprites, with two draws per site.
The existing terrain clock pauses the effect. Level changes immediately hide
stale geometry and coalesce reclassification; disable and map exit release it.

[Waterfall evidence](validation/waterfalls-2026-10-09.json) records **1,201 passing
checks in seven runs and 111 captures**, including the graphics metadata check.
All 22 base and 40 LiA maps were classified; accepted base sites occur in
zone11/zone13/zone3obr and LiA sites in zone10/zone21/zone23/zone26. Flat zone8
adds zero draws. Compatibility, Forward+ and desktop Mobile verify visible
foam/spray, exact pause/restoration, flooding and teardown. The source reference
is R1 `0092dc6e1d7c4aab3f74644a79e9bfca11ecf293` `procedural_falls.h` and its
renderer/geometry call sites. The receipt retains prototype exclusions and costs.
Large-map classification and repeated flood changes can still hitch; this is
not a device/FPS acceptance or a default rollout.

## V5: shared moving clouds and soft sun shadows — 9 October

`gfx_clouds` is optional, default off, on the Weather/effects page. The first
checkpoint is retained as Moving layer (value 1), with the volume extension
below using values 2/3. `clouds.gd` shares one seamless 256²
mipmapped noise texture between two scales, the sky, sun-shadow projection and
enhanced water's custom Fresnel reflection. The sheet sits at 160 m and fades
at grazing angles to preserve authored perimeter fog. No scene draw is added.
Sun occlusion is capped at 28%; ambient, local lights and emissive contributions
remain unchanged. The same policy covers material highlights and leaf transmission.

The terrain owner integrates the existing weather-wind direction against game
time, with independently wrapped phases. Changing weather does not multiply a
new direction by total elapsed time. Gipat, Ingos and Suslanger have distinct
fair-weather coverage; current rain/snow increases it. Held clocks freeze coverage,
motion and cloud-mode star twinkling. Caves clear immediately, night has no sun
shadow, rewinds reset deterministically, and old/retained worlds cannot overwrite
or clear the active view's globals. Global shader specialization removes the
cloud samples when disabled. The shared texture uses the existing bounded noise
cache; per-map phase ownership ends on disable/exit. Original cloud-off sky behavior
and UI preview materials are preserved.

Implementation: `game/src/game/fx/clouds.gd`, `game/src/game/gfx.gd`,
`game/src/game/sky.gd` and the terrain publication/lifecycle hooks. The option's
EN/RU/DE metadata was validated and committed with `4a595dc`. The optional
volume extension follows below; physical-device costs remain separate work.
Localized weather mist is implemented in the subsequent V5 section.

[Cloud evidence](validation/clouds-2026-10-09.json) records **193 passing checks
in five final private runs**, with 45 captures. Base and LiA headless policy/
lifecycle checks pass; Compatibility, Forward+ (material lighting enabled) and
desktop Mobile pass rendered sky, sunlight-only occlusion, water reflection,
exact held day/night, cave clearing, disable restoration and UI-preview controls.
The scene adds zero draws. These are functional Linux checks, not FPS or device
measurements; the LiA run is a profile/lifecycle check, not a rendered map census.
A first Mobile post-recompile capture differed at two water pixels (peak 2/255),
while later cleared/restored captures were exact. The final fixture waits for
native asynchronous pipeline specialization before that strict comparison.
The rejected run and earlier fixture/parse errors remain in the receipt.

Accepted private export: `renderer-followup-20261009/clouds/clouds-final2`,
runtime SHA-256 `090f2254527771465e745bb887386978dfca069ef1943b3b9bcadcad1a377a44`,
PCK `3fcc4ce093103ec85e79b3b5396f0a6cd921ec85442aff9b7d878461daee3d28`.
Reproduce with `clouds/run.py`, `tests/clouds.gd`, the selected renderer and
`--fresh-cache --build=clouds-final2`; add `--headless`, `--astral`, or
`--clouds-materials` for the recorded variants. Tests and commands are frozen
beside each manifest. Production and test source hashes are in the receipt.

### Cloud correction: shared ground-contact light

Combined V6 review found that `GroundContactShader.contact_light` independently
reconstructs terrain illumination and had missed cloud attenuation. A blended
object base could remain brighter than the cloud-shadowed ground. `Gfx.compose`
now applies the same factor to that function's sun term, before native byte
packing. The focused [contact-light receipt](validation/cloud-contact-light-2026-10-09.json)
records the baseline failure and **15 passing checks across three backends**:
a uniform cloud shadow exactly matches reducing only the original sun, while
ambient/local light and the zero-night-shadow control remain exact. The real
combined terrain/contact captures are recorded with the subsequent V6 checkpoint.

## V5: optional cloud volumes and camera-height correction — 9 October

The existing **Moving clouds and shadows** row now offers Off, Moving layer,
Volume: Low and Volume: High. Off remains value/default 0; Moving layer keeps
value 1 and its prior pixels. Automatic presets do not enable the new modes.
All four choices and the fallback tooltip are localized in EN/RU/DE and fit
the existing settings page. No additional row was added.

The new desktop Vulkan path generates periodic 128³ Perlin/Worley shape and
32³ erosion textures once per active lifetime. Low uses a quarter-resolution
sky pass, up to 128 view samples and three light samples; High uses a half-
resolution pass, up to 256 view samples and five light samples. Stable midpoint
integration replaced failed sparse jitter variants that showed comb/checker
patterns while paused. Enhanced water uses the same density, phases, lighting
and storm composite, with up to 85 reflected-ray samples. Solar attenuation
uses eight density samples per receiver, retaining the 28% sunlight-only limit
and existing contact-light parity.

The user's low/strange-cloud feedback prompted a raised 2200–5800 m layer,
separated rounded fair-weather cumulus, denser precipitation types, gradual
distance thinning and a softer storm horizon. Matched camera/seed/time captures
and 9°/20°/35° gameplay-pitch views retain the before/after evidence. The
preferred fair and storm versions were independently inspected. Low retains
visible quarter-resolution softness in small wisps; doubling its integration
steps did not materially improve that tradeoff. Original perimeter-fog
composition still runs after the clouds.

Six wrapped double-precision phases follow existing game time and weather wind.
Held frames preserve shape, stars and reflections. Disable, sheet selection,
cave entry and active-owner teardown detach shared texture views and release
the two backing RIDs; stale owners cannot clear their successor. Compatibility,
headless and constrained-platform policy retain the sheet. Desktop Mobile also
requires native capability `ei_sky_subpass_alpha`; older runtimes fall back.
The separate native checkpoint `57434fc` preserves ALPHA data and conditionally
uses higher precision only for sky subpasses that need it, retaining all nine
prior engine patches and the original 0/1 allocations/images.

[Volume evidence](validation/cloud-volumes-2026-10-09.json) records **694 passing
checks in eight final runs, 109 independent full-RGB assertions and 133 captures**.
It covers Gipat and close-water Ingos geometry, day/night, rain/snow, isolated
water reflection, empty density, exact held/cave/off controls, live qualities,
old Mobile/Compatibility/headless fallbacks and repeated resource ownership.
The [native receipt](validation/sky-subpass-alpha-2026-10-09.json) separately
records 168 engine checks and 59 RGB assertions, including ten reproduced
old-runtime alpha failures and exact ordinary/RGB-only controls.

With a 1920×1080 SubViewport, active shadows and water reflection, one clean
RTX 3090 Forward+ view measured GPU medians of 0.780 ms off, 1.349 ms sheet,
2.335 ms Low and 4.946 ms High over 60 settled samples each. These are costs
for that fixed scene; no device/FPS rollout acceptance follows from them.
The bounded adaptation reuses existing 2D weather noise and has no temporal
history/reprojection, cached solar projection or spherical atmosphere. Full
R1 parity, physical-device acceptance and broader weather/readability coverage
remain open. Parent-owned final combined-pack composition and actual-Game
lifecycle checks are separate from these counts. The frozen private bundle is
`volumetric-clouds-20261009/volume14-native`; all eight production files match
its export. Installed templates and release packages remain unchanged.

## V5: bounded local water mist — 9 October

`gfx_weather_mist` adds local morning, night, swamp and lingering-rain mist
through the existing native Forward+ volumetric pass. It requires
`gfx_volumetric`; Compatibility and Mobile allocate no mist volumes. The option
is default off on the Weather/effects page. No global environment density,
original perimeter fog, gameplay unit, navigation or network state is changed.

`weather_mist.gd` owns at most six FogVolume boxes in a local three-by-three
12-metre cell neighbourhood. Boxes are at most eight metres high. Up to sixteen
6² float source masks are cached; construction advances at most twelve texels
per update with a soft two-millisecond budget. `weather_mist_sources.gd` reads
actual authored non-emissive liquid triangles, mean heights and scripted flood
offsets. Centre/corner coverage taps and boundary erosion give up narrow water
and shore wisps; this is sampled conservative coverage, not a geometric proof
for every point inside a texel. Caves, unknown regions, other liquid classes
and Ingos open water are excluded. The shared habitat query skips its unnecessary scenery index.

A pausable Game owner uses terrain time, the existing weather/wind state and
bounded phase integration. Terrain replacement, held-clock floods, rewinds,
loading/travel/movie gates and disable/reload are covered. Mist has no shader
TIME or emission. This adaptation uses a 60% daily morning chance and a two-hour
wetness decay scale, rather than the pinned reference's 35% and four-hour policy.
Its maximum density is approximately 0.01429 per metre, below the reference's
full-morning open-water 0.05. Disjoint cells bound the continuous-field added
optical depth to one along any ray (a conservative 63.3% opacity ceiling).
That mathematical ceiling is not a universal party-contrast guarantee.

[Mist evidence](validation/weather-mist-2026-10-09.json) records **304 checks
across seven wholly passing runs**, plus a separately retained LiA run with
**52 of 53 checks passing**. Native history, empty-source and restoration
controls remain within one or two channel levels in these views. Original
figures remain visible; a character viewed through the mist at a 14.74-degree
camera angle retains 96.9% dawn and 97.6% post-rain contrast in the sampled
silhouette. Base swamp and unsupported-renderer controls pass. The LiA clear-noon
motion comparison changes 19 channels above 2/255 against its strict threshold
of more than 20; its presence, pause, restoration and readability controls pass.
The failed criterion is preserved, with no further appearance tuning to cross it.
Earlier ineffective density prototypes, a high-density diagnostic and invalid
camera/figure fixtures are excluded and retained separately.

The actual-Game integration also verifies visible mist alongside clouds,
ambient life and the optional camera lens. Full regional routes, froxel artefacts
outside the sampled shore rays and device costs remain open. This adds local
weather fog; the optional cloud-volume extension above is a separate bounded adaptation.

## V3: bounded ambient animals and regional particles — 9 October

Accepted in `78fbd79`. Separate World/textures options for ambient wildlife and
regional particles default off. `ambient_life.gd` owns at most two ground
residents, three birds and 192 particle quads near the view. Original rat,
spider, toad and bird models/animations supply decorative figures; they never
enter GameUnit, collision, navigation, save, network or gameplay RNG state.
Fixed hashed placement cells, bounded cooldowns and visible-unit threats limit
population churn and suppress decoration during nearby combat. All animation,
movement and emission use the pausable terrain clock and existing weather wind.

`ambient_habitats.gd` reads actual jittered terrain/liquid triangles, scripted
liquid offsets and relevant authored scenery. `ambient_ground.gd` places small
animals on the visible loose-ground surface, including actual CPU footprint
images and dense subdivision, and re-seats held poses when terrain options
change. This corrected a real test failure where raised snow buried a mouse.
`ambient_models.gd` and `ambient_particles.gd` retain bounded presentation state.
Regional effects cover pollen, deciduous leaves, Dead City motes, cave dust,
lava embers, desert dust, snow motes and Gipat night fireflies. Base zone9 and
LiA zone9 retain their different habitats.

[Ambient-life evidence](validation/ambient-life-2026-10-09.json) records **1,088
passing checks over 15 isolated runs**, with inspected base/LiA regional images,
three desktop backends, world/clock/option lifecycle, threat visibility and the
snow/footprint regression. The receipt distinguishes earlier unaffected particle
captures from the final visible-ground source snapshot. Small animals remain
subtle; original model parts can add up to 61 mesh submissions, and the particle
field adds one. These bounds do not establish a frame-time benefit. Long routes,
physical devices, extra species, perching and carrion behavior remain follow-ups.
The regional test views also retain existing map-edge fog rather than retuning
unrelated terrain/lighting for attractive screenshots.

## V6: optional verified rock projection — 9 October

Accepted in `7c0f2d6`, with default-off metadata from `13d8de0`.
`terrain_cliff.gd`, `terrain_cliff_shader.gd` and the generated original-atlas
metadata project existing rock artwork from two side planes on verified plain
natural-rock slopes. The effect fades in between 40 and 55 degrees and out
between 80 and 140 metres. Adjacent-facet guards preserve flat ledges and blend
eligible neighbours symmetrically. Original terrain, the live colour-cache
material and rigid-scenery ground contact share the same helper and fields.

Classification uses exact original atlas fingerprints and four matching authored
Stone/Rock corners. Paths, transitions, unknown or modified atlases, unsupported
packed flags, snow/ice/liquid types and invalid geometry retain their previous
appearance. Original triangle geometry, navigation and collision stay unchanged;
there are no additional draws. Existing tile-edge blending, painted relief,
macro variation and wet banks remain authoritative. Broad material-transition
reconstruction and geometry rounding are separate work.

[Cliff evidence](validation/terrain-cliffs-2026-10-09.json) records **888 passing
runtime checks**, **83 independent full-RGB image assertions** and 117 captures.
A 62-map base/LiA census validates source admission. Three desktop backends
cover default-off/unknown/disabled restoration, cached ground colour, and
composed clouds, materials, surface weather, caustics, currents, waves and
ground contact. That combined work found and corrected the independent contact
sunlight path described above. The initial Mobile async-specialization residual
is retained separately; settled comparisons pass. Functional Linux validation
does not establish device or frame-time acceptance.

## V6: opt-in authored natural transitions — 9 October

The existing **Terrain detail** row now offers Original (0), Detailed (1), and
Natural transitions (2), with English, Russian and German choices. Detailed
remains the default and the automatic preset value. Original and Detailed are
PNG-identical to the untouched build in all three fixed reference scenes.

At this historical checkpoint, `terrain_transition.gd` and its shared shader
reconstruct only verified pairs of natural grass, snow, sand and rock families. Exact original atlas hashes,
authored rotated corners and present plain tiles from each exact family are
required. Conflicting corners are rejected without voting or borrowing a nearby
material. Paths, liquid/bed families, unknown/modified atlases and three-family
art remain unchanged. An untouched edge strip also preserves the original
painted relief beside unsupported tiles. The improvement is visible in the
light/dark sand boundary in zone15, with grass/limestone and snow/gray stone
controls; original geometry, navigation and collision are unchanged.

The same sampler and bounded per-map texture serve ordinary terrain, rigid
object contact, installed snow/sand footprint meshes and the native colour
cache's live material. Mode 1→2 explicitly refreshes those programs despite
Gfx's shared boolean terrain-detail signature. The contact coarse-colour probe
uses its own traits output so it cannot overwrite the primary sample's traits.

[Transition evidence](validation/terrain-transitions-2026-10-09.json) records
**624 passing runtime checks**, **102 independent RGB image assertions** and
**121 captures**. All 19,000 classified dirt/path/paving pixels remain exact in
the dedicated path view. Three desktop backends, cached terrain, actual installed
footprint receivers, and composed cloud/caustic/cliff/water/contact shaders pass
restore and resource-release controls. The five-map Base/LiA check deliberately
leaves most conflicting LiA zone26 transitions unchanged and zone6 neutral.

This was the conservative two-family material stage, extended below. At that
checkpoint, three/four-family junctions, inferred metadata, broad stochastic
anti-repetition, transition side projection, geometry rounding, long routes and
physical-device cost acceptance remained open.
No installed build, original asset, real save or published release was replaced.

### Three/four-family candidate census

The [read-only junction census](validation/terrain-junction-census-2026-10-09.json)
identified original sites for the junction stage below. It reads all 38 base
and 51 LiA map headers, sector vertices and land codes without constructing map
meshes or GPU textures. Exact atlas identities, allowed natural ground classes,
authored rotations, present plain donors, consistent shared corners and valid
original geometry remain prerequisites. No classification was inferred from a
map name, nearby colour or a majority vote.

| Mounted campaign | Three-family candidates | Four-family candidates |
|---|---:|---:|
| Base, 38 maps | 8,374 | 36 |
| LiA, 51 maps | 8,653 | 35 |

These are tile occurrences, not unique assets or visible pixels; campaigns
reuse maps and artwork. Base excludes 215 junctions with conflicting corners
and 66 with missing donors; LiA excludes 275 and 72 respectively, with overlap
between reasons. The receipt saves separate three/four-family witnesses and
their exact displaced original centre vertices. Useful starting sites include
base zone15 tile `(69,19)` (orange stone/gravel/grayish sand), zone12 `(67,127)`
(winter grass/snow/gray stone, four families), and LiA zone26 `(19,58)`
(black/dark stone/irregular sand).

The two final headless scans pass 12,969 archive/data assertions, mostly sector
structure checks. This is not visual acceptance. Eight-neighbour seam guards,
domain-warp compatibility, liquid/scenery occlusion and complete-frame cost
required rendered controls at this census checkpoint. Its shader follow-up is
qualified below. Independent review corrected witness coordinates to include
authored XY displacement; earlier scans retain identical counts but are excluded
from the final witness record. The existing irrelevant headless screen-space-AA
startup warning is retained explicitly.

### Verified three/four-family junctions

`e866a2a` extends the existing Natural transitions value to every verified
three/four-family candidate in the census: 8,374/36 base placements and
8,653/35 LiA placements. Exact original families, rotated corner identities,
present plain donors, shared-vertex agreement and valid original geometry remain
required. A family is never dropped to manufacture a pair, and missing or
conflicting metadata still leaves original artwork intact.

The optional second metadata plane shares the existing nearest RGBAF sampler.
A continuous one-tile vertex influence field joins the new path to accepted
pair shading; all plain tiles stay authored. The warped lookup consumes the
whole neighbouring family set. Original/warped dominance, guarded displacement,
normalized material shares and continuous softness preserve endpoints and avoid
rank changes at soft/hard boundaries. New-path noise uses stable integer lattice
hashes: actual GPU probes found six discontinuities with a floating sine hash.
Pair-only maps retain the byte-identical legacy program and noise. Junction
maps reuse its math with adjusted metadata bounds/decoding. Exact 24-bit packed
channels decode without adding a floating half, which would corrupt high odd
integers. Contact, footprints and cached land use this same program and texture.

Repeated shader expansion initially stalled composed Compatibility beyond 180
seconds. One legacy call site and one four-tap relief loop preserve the exact
coordinates, gradients and downstream arithmetic. Internal uniforms always
default to four; there is no new graphics option. The final composed test takes
59.80 seconds in its private profile, versus 120.43 before relief consolidation;
all eight images are exact between those variants. These are whole-test
elapsed times, not isolated compile timing or gameplay FPS.

[The junction receipt](validation/terrain-junctions-2026-10-09.json) separates:

- **7,515** final metadata/source assertions. **13,149** all-map admission and
  **144** prior analytical assertions carry forward because the production CPU
  field is byte-identical to the tested candidate03 source.
- **180** final shader checks on Forward+, Compatibility and desktop Mobile,
  containing **19,911 individual GPU probes**. These include independent core
  edges, distinct field representations, dense traces, absent families, packed
  metadata, endpoint/guard controls and 240 patterned relief-tap comparisons.
- **252/253** original-map rendering checks and **107** captures. Original,
  Detailed, neutral and disabled controls match the earlier build. The sole
  strict failure is the same Compatibility contact-edge pixel `(379,229)`,
  peak RGB delta 70, also present in the baseline neutral-versus-Detailed check;
  both builds' neutral images match exactly. It is retained, not relaxed.
- **19,000** path pixels remain exact. All changed pixels in the old pair views
  lie within the junction influence area plus one tile for relief taps. The
  classification pass disables fog and hides transparent water so it can label
  the underlying terrain; actual comparison images keep the original water.
- **54** complete-viewport cost checks at 1920×1080: Detailed/Natural/Natural/
  Detailed, 96 warm-up and 240 sampled frames per arm. Geometry submissions and
  Detailed images stay exact; the existing-pair Natural cost image is exact too.
  Final three/four-family Natural GPU medians range 1.181–1.533 ms in these
  close views. Other rendered processes were observed during both runs, so these
  are descriptive diagnostics, not clean cost acceptance.

There are **119 final captures** including the shader and timing fixtures.
The largest actual field texture is 2 MiB; texture and retained packed row
payload are each bounded at 8 MiB for the maximum tile count. These are payload
bounds, not total process/driver memory. Pair-only maps retain one plane and the
old program. The final private pack is candidate09, with all 613 committed game
files matched; among 99 generated files, only the two transition script UIDs
were regenerated. Both native binaries and all gameplay/settings/cloud sources
remain unchanged. Full R1 parity, inferred atlas metadata, general anti-repetition,
transition side projection, geometry rounding and clean device/long-route costs
remain separate work.

## V8: guarded optional camera depth of field — 9 October

Accepted in `a533078`. `CameraDepthOfField` applies the pinned R1 25-to-50-degree
pitch fade and strength 0.2 to a far-only Godot lens. It follows the rig's actual
orbit, dialogue or direct-control target with 0.3-second log-space smoothing.
This transfers the camera policy without R1's median nine-depth-sample focus.
Tactical views, movies, transparent previews and unsupported backends release
the lens. Prior camera/world attributes restore, and an external attribute
owner takes precedence. Canvas UI remains outside the 3D blur pass.

The ordinary native low-quality kernel produced foreground colour halos.
`engine_patches/godot-4.7/far-dof-sharp-guard.patch` therefore adds a narrow
far-only guard: existing full-resolution targets, exact sharp-texel returns,
integer taps, sharp-source rejection and corrected raster pixel centres.
Clear sky remains sharp as a conservative boundary policy. Near-enabled
legacy kernels are unchanged. `OS.has_feature("ei_far_dof_guard")` is a native
capability; stock and earlier runtimes cannot accidentally activate the lens.
The optional setting defaults off on every graphics tier.

[Depth-of-field evidence](validation/camera-depth-of-field-2026-10-09.json)
records **657 passing checks in 15 retained runs**, including strict foreground,
focus, font/UI and sky-boundary controls on Forward+ and Mobile. All **26
old/new near-only and near-plus-far image pairs are exact**. The original
actor-visible Dead City dialogue pair was inspected qualitatively; failed
freeze-fixture captures are excluded from acceptance. The ninth patched Linux
runtime is private at `camera-dof-20261009/build-guarded/CPU.x86_64`, SHA-256
`769dd027c0b444caca0d5fbbb6014eda80970e991e9f32fdb1f86ec385d20c3e`.
This is not full R1 horizon/focus parity, a platform rollout or a performance claim.

## V7: neighbouring-map scenery requires verified placements

The pinned R1 implementation reads `world-map-layouts.json` beside its addon.
Its actual call site admits only a verified `deja-vu` resource profile identified
by `databaseJmv.res`, then selects that profile from the layout. The parser accepts
schema 1/2, layout algorithm 1 and `mpr-local-xy`, with explicit profile, allod,
zone/component identities, origins and optional resource paths/dimensions.
Those placements are external input; none is committed in the pinned source.

A filename search under `/home/llm2x/Documents`, including both available game
data roots and the reference repository, found no such layout. The user has been
asked for its local path if available. Base and LiA map names, world-map icons or
travel links do not establish geometric adjacency. Do not invent origins, reuse
Deja-vu placements for a different campaign, or load neighbour gameplay worlds.
This stage remains data-dependent; no inactive settings switch or speculative
streamer was added. Resume with a verified layout for the actual mounted campaign,
then validate connected edges, independent materials/liquids, bounded residency
and actor/script-free teardown against the audit's V7 acceptance list.

## Combined cloud and co-op acceptance — 9 October

That earlier private Linux export freezes committed application revision
`79bee8a56f7a27a9897ae9ebe44fa6000d94cf21` at `/home/llm2x/Documents/EI/local/scratchpad/renderer-followup-20261009/integration/cloud-coop-final-01`.
Import/export completes without errors and excludes no working game changes.
[That checkpoint's evidence](validation/renderer-coop-integration-2026-10-09.json)
records **711 passing checks and 60 captures**:

- **156 renderer checks:** High cloud volumes and Natural terrain transitions
  compose with the existing water/contact/weather effects on Forward+, qualified
  desktop Mobile and Compatibility fallback (28 each). Actual Game/world lifecycle
  adds 72 checks through pause, load/travel/movie gates, live options, volume
  resource release, zone replacement and rejection of retired owners.
- **398 settings checks:** five pages and both entry points fit 800×600 in English,
  Russian and German, with mouse, controller-key and touch dispatch. The 21
  captures show default choices; weather-page samples were inspected. Cloud value
  label widths are separately recorded in the volume receipt.
- **157 final-export gameplay checks:** LiA compatible personal reimport and
  original chapter travel (94), fresh-process solo load of both network-produced
  saves (21), original pending dragon action/cooldown on solo return (27), and
  base NEW joining after opening initialization then returning at the first
  village (15). Own hero, private purse, quests and actual position survive.

The renderer/settings runs use the committed `7c593aa` pack. Comparing all 712
frozen application files against the final export finds exactly one difference:
`src/game/coop_progress.gd`, containing `79bee8a`'s bounded fresh-start fix. Every
other file and both native binaries match, so unchanged renderer scenes were
not repeated. Feature-specific evidence remains separate, including the fresh
start fix's 239 checks and the main solo-return fix's 803 checks.

| File | SHA-256 |
|---|---|
| `CursedLands.x86_64` | `fa2a3139b82b5cc7eef61f2e91c30944910435ad7aaec5490ab450cb4c9504f5` |
| `CursedLands.pck` | `4a6242634eb82c56ea3c2a9be79b565a190a210a05157348f91297e15dafd9ef` |
| `libterrain_search.so` | `d20a296e4076d7cff681c24fbda0d853d1e272de499b22592c855eeade4a783e` |

There are no failed assertions or script/runtime errors in these runs. The
existing Compatibility screen-space-AA warning is retained; one independent
headless editor import overlapped that functional run. These are functional
Linux checks, not performance, full campaign or Windows/internet acceptance.
Original data and user saves remain untouched; no build was published or installed.

## Earlier combined follow-up acceptance — 9 October

The final private Linux export freezes committed application revision
`57e49cb9c57e1a66b4d4aa0f7fb2353597b9d962`. No uncommitted game changes were
excluded. Import and pack export complete without errors. The binaries are:

| File | SHA-256 |
|---|---|
| `CursedLands.x86_64` | `769dd027c0b444caca0d5fbbb6014eda80970e991e9f32fdb1f86ec385d20c3e` |
| `CursedLands.pck` | `ed5456d9423a8934d886a214d8b66234de4be0280ca38d36bc8b40c4b2a881de` |
| `libterrain_search.so` | `d20a296e4076d7cff681c24fbda0d853d1e272de499b22592c855eeade4a783e` |

[Combined evidence](validation/renderer-followup-integration-2026-10-09.json)
records **859 passing checks and 60 captures** across three complementary scopes:

- The core renderer fixture deposits real actor wave history with the other
  terrain, water, contact and atmosphere options enabled. Three backends pass
  28 checks each; camp and corrected ENet queen fixtures bring this core scope
  to 210 checks and 33 captures.
- The actual `Game → World → Map → Terrain` lifecycle passes 125 checks and
  six captures. Three decorative animals, 94 particles and six mist volumes
  coexist with clouds and the real camera lens. Pause, loading/travel gates,
  option changes and actual zone replacement retain correct ownership. Each
  rendered toggle exceeds held-image variation. All 256 application GDScript
  hashes and both native binaries match the final export exactly.
- The final pack passes 398 settings checks, 88 camp checks and 38 original
  poison-source-three ENet quest/save/reload/reconnect checks. All 21 settings
  captures are 800×600; the five pages and both entry points fit in English,
  Russian and German. Mouse, controller key routing and touch dispatch pass.
  Remake localization is exercised over the mounted English original assets;
  this is not acceptance of every original-language data pack or physical pad.

Two failed setup runs are excluded explicitly: the first queen test closed its
peer before clearing its online state, fixed only in the fixture by `b742ddc`;
the first settings launch let the default display profile override the CLI
resolution. Its replacement seeds the established private minimum-size profile,
without changing production or test source. Feature-specific prototype failures
and the LiA mist 52/53 partial result remain in their own receipts. These totals
do not imply every feature matrix passed or that the broader backlog is complete.

This is functional Linux validation. Original assets, real saves, installed
builds, templates and published releases remain untouched; source Experimental 6
and protocol 13 remain unchanged. Device costs, sustained playthroughs and the
data-dependent V7 work below are still open. The later supplied-save U45
investigation is recorded in the gameplay handoff.

## Combined P1/P2 texture acceptance — 9 October

The private `texture-coop-final-01` export freezes committed source
`63c16788f1bba2be73d1a00d534b310a4bf0fc98`, with the qualified `fa2a3139…`
runtime and `d20a296e…` native helper unchanged. Its PCK SHA-256 is
`5a3847a25a7a46d99f63c2f13ef76331556fc6bdd6b504dada47dfab2d90dfcb`.
[Combined evidence](validation/renderer-texture-integration-2026-10-09.json)
records **190 runtime checks, 23 independent saved-image comparisons and 37
captures**, with no runtime errors or foreign Godot processes.

The actual Forward+ Game/World/Terrain test passes 134 checks. Compressed raw
arrays survive effect toggles and world replacement; cloud volumes, mist,
ambient life and camera ownership retain their earlier controls. A real posed
GameUnit and Paperdoll share wounds through ordinary asynchronous publication,
selection, healing and authored equipment replacement. World images exclude
HUD health pixels. The old figure is retired while the Paperdoll viewport is
retained, framed and paired with the new model. Compatibility and Mobile each
pass 28 composed terrain/water/cloud shader controls, including persistent waves,
held clocks, alternate liquid branches and exact off/re-enable restoration.
Full-RGBA image comparisons independently confirm the saved control images.

All 712 frozen post-import files match the accepted P1 candidate. Its manifest
was captured before import and omitted 30 generated `.gd.uid` sidecars; a
separate hash comparison of the actual post-import stages resolves that initial
manifest-only mismatch. Relative to the earlier `79bee8a` combined pack, only
`terrain.gd`, `unit_model.gd`, `unit_wounds.gd` and `order_marks.gd` differ.
Gameplay source is unchanged: the previous co-op/solo evidence is retained,
not rerun or added to these totals.

Two setup runs are excluded. The first prototype included HUD health changes
and held replacement figures before explicitly posing them. The first revised
run passed wound presentation but correctly lost ambient re-admission because
the prepared hero remained on its habitat patch. Restoring the original actor
position/camera before the inherited lifecycle checks fixes the fixture; no
production code or tolerance changed. Both records remain linked.

This is Linux RTX 3090 functional acceptance. It does not establish Windows,
Android, browser, sustained combat or FPS results. P1 Mobile precision/custom
material limits and P2 compressed/tail colour differences remain in their
feature receipts. Source Experimental 6 and protocol 13 remain unchanged; no
release, installation, original asset or real save was modified.

## Original prison alarm: late arrival and absent reload — 9 October

`7e31470` fixes a reproduced `gz19h` area-1 alarm gap. Original startup registers
one native wait for each hero present at that moment; later guests entered the
area without any wait to detect them. A persistent registrar now adds the same
unaltered wait once for each newly eligible character. The exact 23-definition
original AST and startup call must match before this adaptation is admitted.
Native guard dispatch, delays and reset calls retain their original bodies and
saved instruction indexes.

A saved native continuation also retains its stable hero reference while that
character is absent. Two host-only reloads preserve the pending wait and native
remaining delay; a normal ENet return rebinds the same instance. Co-op-to-solo
projection retains the recipient's pending/spent registration state. Legacy
saves recover only when an actual native registration or continuation proves
that the family was active; missing history is not guessed.

[Prison alarm evidence](validation/prison-alarm-late-join-2026-10-09.json) records
**331 passing candidate checks**: 70 state controls, 75 early-arrival and 75
late-arrival ENet checks, plus 111 existing captivity/projection/solo-return
regressions. The corrected original-startup baseline passes 45/45 early checks
but fails 8/45 late checks. A reviewed pending-intruder ordering defect fails
one of the same 70 state checks in candidate01 and passes in candidate02.
The final network runs load the original reinforcement MOB and all eight real
guards receive the authored target after the returning guest enters.

These are prepared-position, controlled-clock network fixtures and serialized
edge-state tests, not a full physical prison playthrough. Setup failures remain
in the receipt. A foreign rendered process overlaps the state test, so its
elapsed time is not a performance result. All 613 committed game files match
the 712-file candidate02 stage; only four production scripts and two generated
UID files differ from terrain candidate09. Native binaries, graphics, settings,
protocol 13 and save schema are unchanged. No user save or installed build was
modified.

## Original prison treasure discoveries: late arrival — 9 October

`518c2b5` fixes two further original `gz19h` startup gaps. The native `qk16h`
and `qk17h` discovery checks only watched heroes present during map startup;
late co-op guests could reach the same areas without advancing shared discovery.
The early baselines pass 27/27 and 29/29 checks; the late baselines fail five
checks each (22/27 and 24/29). These are discovery stages, not chest rewards.

Only six original check definitions gain shared-party metadata: qk16h
#265/#269/#271/#258 and qk17h #279/#280. Complete native families, their exact
WorldScript calls and the original unique HChest1 binding are validated before
admission. Changed definitions reject their own family independently. The
original qk17h reference to HChest1 is retained; HChest2 completion and all chest
opening/reward bodies remain unchanged. Existing shared-check machinery keeps
original instructions and timers and handles absent owners, old waits, spent
checks and solo-return projection. Dead, hidden and disconnected actors do not
trigger discovery. Separate native approach checks may still repeat an
idempotent stage assignment, as originally authored.

[Discovery acceptance](validation/prison-discovery-late-join-2026-10-09.json)
records **431 passing checks**: 139 source/state controls, four 29-check actual
ENet discovery runs (two quests, early and late), 31 captivity checks, 70 alarm
state controls and the 75-check alarm network/reload regression. The last
retains two absent host reloads and normal rejoin before all eight original
guards receive their orders. Discovery runs use original WorldScript and normal
network registration, with controlled actor positions, paused unrelated combat
and explicit native ticks; they do not establish a full physical prison route.
The first state attempt had a fixture-only type-inference parse error; it is
preserved separately and excluded from acceptance. Foreign stock Godot jobs
overlap some headless runs; no timing or performance claim is made.

All 613 committed game files at this checkpoint match its 712-file candidate01
stage. Only `story_compat.gd` and its generated UID differ from the prior
qualified prison-alarm candidate02. Native binaries, graphics, settings,
protocol 13 and save schema are unchanged. The separate in-progress renderer
candidate is excluded from this qualified gameplay export. No supplied save,
original asset or installed build was modified. Other q71h/q72h source leads,
full routes and platform coverage remain open; they are not part of this fix.

## Terrain and cloud cost attribution — 10 October

The unchanged `local20261010.1` package now has separate surface, moving-sky
and water-reflection measurements. The 2560×1440 surface fixture passes 68
execution controls; the moving-cloud fixture passes 74. These are Linux RTX3090
diagnostics, not Windows FPS or an optimization acceptance. The moving-cloud
run overlaps another rendered process at startup, and GPU clocks are not locked.
Its High sky medians are about 6 ms; the isolated enhanced-water path adds about
2 ms with clouds. Ground-only measurements exclude both of these paths.

Single-sector main-device Natural cache experiments retain the actual donor
sampler and independently evaluate each mip. At 48 pixels/tile the compact
colour/traits textures use 11.4 MiB per sector including its gutter/mips.
Resolution, boundary masks and caching only the Natural delta all have recorded
quality/performance tradeoffs; none is promoted. Exact held/restored images are
controls, not evidence that cached colour or normals are exact. Failed shader,
SNORM-format and initially capped benchmark runs are retained and excluded.

The next planned proof at this checkpoint was a bounded horizontal weather
lookup, retaining live vertical density, shape, erosion and scattering. Its
results now follow below. Do not add map residency around the unresolved
Natural colour-cache prototype yet.
[Full evidence and frozen fixtures](validation/terrain-cloud-cost-prototypes-2026-10-10.json).

## Cloud sampling investigation — 10 October, continuation

The bounded horizontal-weather proof is complete as a scratch investigation,
not a production optimization. Four main-device GPU field variants, a direct
phase-term hoist, and a High sky-resolution experiment were run against the
unchanged local20261010.1 package at 2560×1440. Frozen source, images, timings,
all strict residuals and 148 verified evidence-file hashes are retained in the
[cloud sampling receipt](validation/cloud-sampling-prototypes-2026-10-10.json).
No game source, settings, engine, gameplay protocol or delivered package changed.

- The 8 MiB linear field has visible numeric edge differences (High peak 23);
  the 32 MiB version reduces High mean maximum-channel error to 0.134/255,
  peak 8, while its approximately 0.061 ms update precedes the viewport timing.
  High paired viewport medians are 5.533/5.457 ms original versus 4.748/4.685 ms
  cached. This is a narrow, contended Linux measurement, not a Windows gain.
- A smaller field improves agreement but loses the savings. Quadratic mapping
  with RGBA16_UNORM retains the broad domain and lowers High mean error to
  0.052/255, peak 4, but adds lookup math and still costs 32 MiB. Low shows no
  useful gain. Neither cache earns production ownership/residency work yet.
- Moving the ray-invariant scattering terms outside the loop produces tiny
  sky differences (22/6 pixels, peak 1 for Low/High) and exact water images,
  but does not establish a worthwhile performance improvement. It is unpromoted.
- Keeping High's 192/5 integration while changing its sky pass from half to
  quarter resolution gives 5.444/5.452 ms original versus 2.735/2.891 ms in the
  prototype. Low stays byte-identical. Full-resolution images were inspected:
  small cloud features soften. High mean error is 0.774/255, peak 37; this is a
  quality tradeoff, not equivalent output, and is not silently substituted.

All six runs overlap other rendered processes. Of 552 harness checks, 19 strict
image-stability controls fail; the later captured residuals are one colour level
and also occur in unchanged arms. Their cause is unproven. No failure or threshold
was discarded. Runtime errors, texture ownership failures and crashes were not
observed. This is investigative evidence, not an acceptance pass.

The next cloud step is a bounded visual qualification of the spatial-resolution
tradeoff in actual gameplay and varied fair/storm/horizon views before deciding
whether it belongs in an existing quality choice. Do not repeat these six
prototypes or claim the Windows 9 FPS report resolved. The Natural sector cache
and V1 terrain-contact composition remain separate, unpromoted scratch work.

## Cloud radiance ownership and shutdown repair — 10 October

The selected optimization keeps Low's quarter-resolution 96/3 integration
and High's half-resolution 192/5 integration. It skips cloud-volume marching
only in the radiance octmap when the owning Environment has no consumer.
Screen-space cloud samples and base sky generation remain unchanged. There is
no weather cache, new graphics control or implicit quality reduction.

`EISky.update` accepts the actual Environment from Game and MenuScene. Unknown
owners retain full radiance, as do enabled reflections, sky-capable ambient,
volumetric fog, aerial-perspective fog and SDFGI. Source inspection and rendered
negative controls confirm that volumetric fog consumes sky radiance even with
colour ambient. The existing water/reflection policy is preserved; this is
therefore a conditional saving, including the menu, rather than a universal
gameplay cloud reduction.

The production guard preserves every pixel in the authored Ingos original-MP
snow map, Gipat rain and Gipat night static/panning comparisons (90 checks).
Consumer tests exercise reflection, ambient, both fog paths, live changes and
the actual menu. An isolated 1440p moving-sky ABBA sample measures Low at
1.60–1.66 ms full versus 1.08–1.11 ms omitted, and High at 5.85–5.93 versus
4.37–4.48 ms. This is viewport GPU time on Linux RTX3090, not full-game or
Windows performance. Three strict High held checks still differ by 1/255,
including an original arm; their failures remain recorded.

Separate-thread teardown exposed an intermittent native shutdown hang.
The debugger captured empty queues and four sleeping workers, with only one
acknowledging `PRE_EXIT_LANGUAGES`. The eleventh desktop patch wakes missing
acknowledgements after the queues drain, including when the observing worker
already acknowledged before processing more work. Normal scheduling is
unchanged. Four patched Linux process runs exit normally and pass 207 checks;
all 66 native before/after images are exact. The Windows template cross-build
and unchanged import audit pass; Windows execution remains open.

[Evidence](validation/cloud-radiance-2026-10-10.json) retains all 32 investigation
runs, including invalid early fixtures, the wrong-map snow probe, strict
residuals, intermittent exit failures and debugger harness failures. The
quarter-resolution High and weather-cache prototypes remain unpromoted.
Existing V1 scratch changes are excluded. Updated local packages are recorded
separately; neither this change nor a local package establishes stable release
or target-device acceptance.

## Next work in the established order

1. **P1/P2 remaining texture work:** shipped unit/preview materials now share
   native-size wound-only textures over unchanged bases, under the explicit
   sampling/lifecycle contract above. Unsupported custom materials keep their
   legacy bake; eager CPU source retention is now removed from shipped outfit
   producers, with exact uploaded-base/mip and custom-readback controls above.
   Target-device measurements remain.
   Do not claim original two-pass or old baked-pixel equivalence. P2's HD scenery path now avoids the main-device round trip on
   RenderingDevice backends, with byte/render/lifetime evidence above.
   P2's terrain follow-up also avoids enlarged atlas readback and final upload,
   with the unchanged fallback and byte/render evidence above. HD-off raw
   arrays now preserve eligible compression and authored mips, with full
   campaign-corpus, sampling and desktop allocation evidence above. Remaining
   P2 work includes any justified HD memory policy and target-device load/memory
   measurements. The final HD payload is still
   RGBA8; do not count cached operations as per-frame savings. Keep the recorded
   pre-existing native exit issue separate from the accepted texture results.
2. **P3 static scenery batching:** the opt-in live manager, complete-light guard,
   movement/fade lifetime and real-map validation are now implemented above.
   The nine-pixel residual is reproduced by the unchanged-renderer control.
   Desktop timing does not establish a net gain despite fewer draws; keep this
   experimental. Finish long gameplay/device acceptance and measure management
   cost against saved submission time on actual Android devices and browsers
   before rollout. Preserve the
   explicit material-change notification contract and logical mesh consumers;
   do not replace this with a naive MultiMesh regrouping pass.
3. **P4 occlusion:** the native terrain/opaque-object diagnostic above now
   measures hidden work. No general desktop gain or complete visual acceptance
   is established. Resume for a specific expensive obstructed scene/device;
   preserve gameplay visibility and validate motion, thin openings, fades,
   deformation and shadows before integration. Do not repeat the forced-draw
   timing approach or assume standard web templates include native occlusion.
4. **P5 local shadows, then P6 directional stability:** stable selection and
   bounded desktop Forward+/Compatibility/Mobile strength transitions are implemented.
   The GLES pass discontinuity is corrected, with a measured GPU tradeoff;
   Android/web retain the existing path until device acceptance. Range/strength
   ranking and per-scan frustum reuse are now implemented. Native Mobile uses
   its existing opacity blend and provides a constrained-device opt-in;
   desktop correctness and the actual platform gate are validated. Full-map/device
   and caster-aware selection acceptance remain open. Disabled wind and rigid
   foliage now permit native whole-map shadow reuse; live fade/contact shaders
   follow the same specialization. Native Mobile requires the accompanying
   engine lifetime/lock patch. Forward+ live shader changes now also require
   the eighth common shader-lifetime patch validated in the mound section.
   The upstream static-depth/dynamic-overlay cache
   and real device performance remain open. The new moving-unit/static-scenery
   Compatibility probe confirms repeated shadow submissions, but its small,
   noisy viewport delta does not justify the unmeasured depth-copy/cache costs.
   Use a costly target-device workload before building that larger engine path.
   For P6, a normal-frame Forward+ fortress probe now retains exact held/return
   images and measures a 0.119 ms whole-viewport shadow-on/off GPU difference.
   It does not justify a larger projection/cache change. Use an actual costly
   or visibly unstable target workload before changing cascade settings;
   low-sun/zoom/moving-caster/cascade/device acceptance remains open.
5. **C1 character batching/skinning:** the rigid prototype above now measures
   submission savings, extra palette cost, light-selection differences and
   changed picking. It loses total frame time in the sampled desktop workload;
   do not enable it or repeat the naive merge as an untested opportunity. The
   concrete requirements for a different implementation are recorded above.
6. **Visual track:** V1 ground-contact blending, V4 water interaction, V2 biome
   ground cover, then the remaining audit features. V1 now has shared production
   storage and an opt-in scenery blend, with the validation and limitations above.
   Resolve cold preparation and finish its lighting/visual acceptance before
   enabling defaults. V4 now has optional contacts/wakes, terrain caustics and river currents;
   propagating wave fields and authored waterfall detail are now implemented above. These options stay
   off pending broader quality/device acceptance. V2 now has the optional
   grass-interaction, dry-land cover and soft-ground root attachment stages above.
   Dry river/swamp banks are now implemented with the conservative shore rules
   above. Underwater cover/mean-depth lighting and the enhanced-water pause
   correction are now implemented, followed by sparse snow/verified-sand mounds.
   Zone7/zone8 coastal profiles now provide authored sandy-beach acceptance,
   with cover habitat kept separate from breaking surf. Verified atlas-family
   placement and shared vegetation weather wind are also implemented above.
   Native cover index LOD and fully faded submission culling are now implemented
   above, followed by the regional cave/Dead City checkpoint. Survivor compaction,
   long routes and device acceptance remain separate work.
   Preserve the coastal mean-depth boundary limitation and the mound
   Mobile restoration limitation and construction-cost evidence. No visual effect
   was silently enabled. V3 now has bounded local wildlife/particles with
   visible-ground placement. V5 now retains the shared sheet and adds optional
   Low/High cloud volumes, sunlight-only shadows and reflected cloud colour;
   temporal reconstruction, cached solar projection and device costs remain
   explicit follow-ups. Localized water mist is implemented with the bounded
   Forward+ adaptation above. Its LiA post-rain motion threshold remains unmet
   in one retained view, without changing the effect to fit the test.
   V6 now projects verified original rock art on steep faces without changing
   geometry. Verified three/four-family transitions now share terrain/contact/
   footprint/cache shading, with the original-map/GPU evidence above. Keep
   the one-pixel baseline Compatibility residual and contaminated timing explicit;
   clean device/long-route cost, wider anti-repetition, transition side projection
   and geometry rounding remain open.
   V8 now applies the optional camera policy with a capability-gated
   native far-only guard. Their larger parity/device follow-ups are explicit in
   their receipts. V7 remains dependent on verified campaign layout data.
7. **Gameplay continuation:** U39–U44 and the separate U45 premature-completion
   fix are committed. The supplied queen autosave has two living required
   creatures; original death-gate completion is verified. A distinct looted,
   script-added actor reload defect is fixed in `1b8b0f6`. The new LiA
   solo/co-op sync request is addressed by shared travel `82b749f`, compatible
   reimport/checkpoints `80c96d4`, stable saved identity `ec79e3f`, pending story
   actions `74c4804` and bounded opening admission `79bee8a`. The latter restores
   NEW-hero joins after the original base startup flags, with 239 passing checks;
   existing saves retain strict story compatibility. `fdf7885` fixes renamed
   guest identity. `7e31470` also fixes the reproduced original prison alarm
   registration gap for late guests and preserves pending waits through absent
   reloads; its earlier acceptance has 331 checks. `518c2b5` additionally fixes
   the two inspected prison discovery families for late guests (431 checks).
   `d13bac0` extends nine original q71h/q72h route checks to late arrivals
   (630 checks, including discovery/alarm regressions). `8195e68` then fixes
   individual damage/Sleep registration and absent reloads in startup family
   #76 (918 checks); authored follower cadence is preserved. Full routes remain open.
   `0cc6cdc` adds only the missing original Gipat entry effect for extra LiA
   heroes (281 checks); the `zone7:981` lead does not reproduce a movement or
   quest-progression defect. Original positions, NPC movement and saved waits
   remain unchanged. Full physical routes and platform acceptance remain open.
   `f3f1494` fixes the independently reproduced LiA Haburu
   camp approach issue; 379 source/command/map checks pass. All five missing
   authored helpers are reachable but absent from the supplied scripts and
   native table; no replacement behavior was invented. Follow the current gameplay handoff
   for original routes, missing-data boundaries and platform-specific reports;
   do not infer further quest fixes from unconfirmed player states.
