# PT materials and transient lighting — 2026-10-24

Local development work based on `origin/main` at `bab580bd43e7d146c341904c3413bcfb471e5d22`, including the Windows DLSS HUD-mask fix, plus the preceding lighting-stability commit `d3d35ed6161571ee3dab6bddd207c5f3cdf4e874`. No published release, tag, version, setting or player-facing string changes.

## Changes

- Refresh PT's light membership every frame independently of the one-second geometry scan. Short spell flashes can now enter the next rendered frame.
- Retain up to 64 nearby local lights, with stable source ordering. Regions over that limit prefer stronger nearby sources. Up to seven lights use exact enumeration; larger lists use four stratified importance samples per path vertex, weighted by receiver distance, range and luminance. Inverse-probability compensation preserves the admitted sources' expected energy. The [PBRT light-sampling discussion](https://pbr-book.org/4ed/Light_Sources/Light_Sampling) describes this estimator.
- Extend history classification to all light records. Gentle fire intensity changes retain bounded history; moving, recoloured, newly enabled and removed sources reject stale lighting. Honour diffuse-only character-assist lights so they do not create metallic highlights.
- Match roughness and metalness when reconstructing reduced-resolution PT onto object and character materials. Geometry checks alone blended glossy/metal lighting across adjacent skin or rough surfaces. Terrain and planted grass retain their existing specialised receivers.
- Clear NRD history pools on an explicit reset. In this integration, `RESTART` retained one frame of old colour while other lights remained active. A real cave capture and a small GPU fixture reproduce it; `CLEAR_AND_RESTART` removes it. Normal accumulation and gentle fire changes keep their existing histories. These are the upstream [NRD accumulation modes](https://github.com/NVIDIA-RTX/NRD/blob/e06852bd545973cb224eb28820b891205cfc1624/README.md); this finding describes the tested integration, not a general NRD defect.
- Pack foliage rest position and the ground-contact band into one vertex-to-fragment varying. Wind, ground contact and volumetric fog now fit the 32-varying limit together.

Both ray-tracing backends and both native NRD adapters were rebuilt. The build tools verify source, pinned dependencies and committed binary hashes.

## Results

The accompanying JSON records runtime hashes, fixture hashes, isolated profile settings, checks and observations. All 306 final-package checks pass. A further 470 DX12 material-shader checks and 104 controller/history checks pass on the same respective source components; those earlier packs are identified separately because they precede the native NRD reset change.

| Reproduction | Before | Final |
| --- | --- | --- |
| 8–64 local lights | Seven-source limit omits illumination and late spells | Exact summed reference matched within 1.2% in the sampled diffuse measurement on both APIs |
| Metal and roughness boundaries, three PT resolutions | All six boundaries blend incompatible lighting | All six retain the boundary with zero measured leakage and no receiver holes |
| Expired blue spell beside an original cave fire | Raw light returns to about 0.027 blue; denoised output retains about 0.202 for one frame | First expired frame returns to about 0.027 on Vulkan and DX12 |
| First spell frame | Denoised blue about 0.052 against current raw radiance about 0.261 | Displayed blue about 0.263, within the current-radiance tolerance |
| Wind + ground contact + volumetric fog | Exceeds the varying limit | All 470 material option/compilation checks pass |

The final regressions cover native NRD resource lifetime and fallback, rigid/deformed history, authored surface maps/detail, foliage transmission, material boundaries and wind receivers. The corrected wind fixture supplies an actual packed material guide, rather than reusing the lighting alpha. Its unrelated foreground remains rejected.

The live spell fixture uses the original cave and brazier, six dim probe lights and production `SpellFx`. It deliberately keeps the geometry poll from expiring before the spell's first frame. The 4K Windows motion fixture keeps genuine DLSS Performance active, uses a 960×540 PT grid and checks SDK evaluations throughout 120 camera-motion frames.

## Performance

GPU Lab benchmark jobs run exclusively on their automatically assigned GPU. No frame generation or image readbacks occur inside benchmark samples. The matched static river comparison uses the same RTX 3090 and interleaves previous/candidate runs: PT GPU medians are about 0.87 ms and 0.84 ms respectively. The close final pair adds roughly 0.08 ms of controller CPU work. Wall-time samples vary with host CPU activity and should not be treated as universal FPS predictions.

The final package's crowded-light benchmark uses the original river, 1280×720 output, PT Low, two bounces and 90 measured frames per case, repeated in reverse order:

| Lights | PT GPU median range | Controller CPU median range |
| --- | --- | --- |
| 7, stationary | 2.10–2.18 ms | 0.32–0.35 ms |
| 16, stationary | 2.56–2.61 ms | 0.36–0.37 ms |
| 64, stationary | 3.96–4.07 ms | 0.48–0.63 ms |
| 64, one moving every frame | 4.12–4.14 ms | 0.62–0.68 ms |

The last case verifies 90 history resets in each 90-frame round, with NRD active. Main-view rendering also costs more with many Godot lights; these numbers isolate PT and controller work. Campaign screenshots use synchronized readbacks and include loading/paused periods, so their visible FPS counters are not performance measurements.

## Scope and reproduction

Graphical runs use isolated GPU Lab jobs, automatic GPU assignment, a free cursor, FPS display and muted audio. Windows tests execute the standard hotfixed Windows binary under Wine/Proton VKD3D. They do not establish native Windows presentation or FG behaviour. The standard NVIDIA DLLs remain unchanged.

The 64-light limit and stochastic sampling remain quality bounds, particularly for dense overlapping sources at low sample counts. Particle sprites keep their original transparency/effects; their illumination is transported through PT. This does not add ray-traced particle geometry or eliminate every low-resolution reconstruction artifact.

Run the packaged game with original game data, an isolated profile and `--tool=<absolute fixture path> --audit-out=<absolute output directory>`. Resolve fixture `res://tools/tests/` dependencies to that fixture directory. New fixtures are `path_trace_many_lights.gd`, `path_trace_material_receivers.gd`, `path_trace_spell_lights_live.gd` and `path_trace_light_performance.gd`. The last requires a GPU Lab heavy job. Use `--pt-dlss` and `rtx_upscaling=4`, `rtx_frame_generation=0` for the Windows wind fixture.
