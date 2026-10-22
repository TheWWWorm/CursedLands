# Path-tracing sampling and reconstruction validation — 2026-10-22

Unreleased follow-up to `69056f92`. The saved baseline package and updated
package ran on the same RTX 3090, at the same ray counts and target sizes.
Windows DX12 runs used Wine/VKD3D; Linux Vulkan runs used the qualified native
engine. These results do not qualify native Windows or other GPU vendors.

The change adds visible-normal GGX sampling with Fresnel-aware lobe selection,
bilinear temporal reconstruction with individual surface checks, and a
world-space plane check when applying traced lighting to raster materials.
Projection changes invalidate temporal history. Still-scene accumulation keeps
an exact pixel correspondence. The twelve render targets, quality scales and
path sample counts are unchanged.

## Quality measurements

The integrator fixture traces 147,456 independent one-sample pixels on a
uniform metallic plane at a grazing angle, lit by a unit sky. Results below
are the red-channel variance **before reconstruction**, not a blurred image
comparison. New mean energy agrees with independent hemispherical numerical
quadrature to within 0.2% across RGB in these cases.

| Roughness | Previous variance | New variance | Reduction |
| --- | ---: | ---: | ---: |
| 0.35 | 0.41917 | 0.02372 | 94.3% |
| 0.65 | 0.14351 | 0.02613 | 81.8% |
| 1.00 | 0.06817 | 0.03839 | 43.7% |

This is a controlled glossy-surface test, not a claim of the same reduction
throughout the campaign. Source data: [before](dx12-path-trace-quality-before-final/path-quality.json)
and [after](dx12-path-quality-smooth-validated/path-quality.json).
Raw captures: [before](dx12-path-trace-quality-before-final/grazing-metal-0.35.png)
and [after](dx12-path-quality-smooth-validated/grazing-metal-0.35.png).

Synthetic histories exercise the real production compute shader with known
subpixel translations and sloped guides. Absolute error against the expected
bilinear result falls as follows:

| Receiver | Previous error | New error |
| --- | ---: | ---: |
| Flat, orthographic | 0.13132 | 0.00010 |
| Sloped, orthographic | 0.17312 | 0.00022 |
| Sloped, perspective | 0.03900 | 0.00006 |

Unrelated depth layers are rejected in all three cases. The old package
deliberately fails the three new interpolation assertions; the new package
passes all 13 quality checks on both APIs.

The receiver fixture renders the actual material lookup on a steep plane,
with and without an unrelated nearer layer. Green indicates matching traced
lighting; red indicates conventional fallback. In the valid-plane measurement
region, coverage changes from 42.5% to 100% at Low, 72.6% to 100% at Medium,
and remains 100% at High. The separate depth-edge cases still reject the
nearer layer. This isolates one cause of lighting seams; it does not eliminate
all thin-geometry or material mismatches in game scenes.

Receiver evidence: [before data](dx12-path-receivers-steep-before/path-receivers.json),
[after data](dx12-path-receivers-steep-final/path-receivers.json),
[before capture](dx12-path-receivers-steep-before/receiver-640-false.png),
[after capture](dx12-path-receivers-steep-final/receiver-640-false.png),
and [depth-edge rejection](dx12-path-receivers-steep-final/receiver-640-true.png).

## Performance

Frozen river view, 1280×720 window, hidden units, water reflections and frame
generation off, uncapped rendering. Each package runs two rounds in opposite
case orders, with 90 measured frames per case after warm-up. The range below
contains the two median GPU times for rays, reconstruction and texture copies;
it excludes acceleration-structure updates and the main raster viewport.

| Mode | Previous RT pass, ms | New RT pass, ms |
| --- | ---: | ---: |
| 2 bounces, Low | 0.442–0.460 | 0.472–0.476 |
| 2 bounces, Medium | 2.285–2.583 | 2.357–2.596 |
| 2 bounces, High | 9.607–9.846 | 10.200–10.346 |
| 4 bounces, Low | 0.574–0.575 | 0.612–0.613 |
| 4 bounces, Medium | 3.028–3.771 | 3.313–3.328 |
| 4 bounces, High | 11.366–11.578 | 11.951–12.091 |

High adds about 0.5 ms to this GPU pass. Medium remains within baseline
variation. Whole-frame medians fluctuate with CPU/scheduling load on this
shared host; this is not evidence of a general FPS increase. New High
four-bounce whole-frame medians were 14.216–14.298 ms, versus
13.636–13.663 ms in the baseline. The shared machine was also running unrelated
work; those processes were left untouched.

Full timing distributions and conventional/one-bounce comparisons:
[before](dx12-path-performance-smooth-before/path-performance.json) and
[after](dx12-path-performance-smooth-final/path-performance.json).

## Regression coverage

The updated build passed **676 assertions in 12 runs**, including:

- DX12 (DXIL) and Vulkan (SPIR-V) path dispatch, emissive transport, bounce energy,
  metallic reflections, accumulation, emitter removal, resize and teardown.
- Outdoor and cave integration, changing lights, character updates, camera
  motion, projection reset, and restoring conventional lighting.
- Compilation and drawing of 144 material variants, covering 470 assertions.
- Native Vulkan sampling, history and receiver tests with validation layers.
- Existing one-bounce scene RT integration after the shared receiver change.
- Path lighting alongside water reflections and production FSR frame
  generation, including resize, pause/resume and both measured FPS lines.

The frame-generation run produced 90 generated frames over a 90-frame sampling
interval and observed 181 presents. Its capture shows **86 FPS rendered /
173 FPS presented**. These are observations from that run, not a promised
gameplay rate. See [results](dx12-path-fsr-smooth-final/rt-fsr.json),
[HUD capture](dx12-path-fsr-smooth-final/rt-and-fg.png), and
[resized capture](dx12-path-fsr-smooth-final/rt-and-fg-resized.png).

Outdoor and cave captures:
[two bounces](dx12-path-trace-live-smooth-final/river-path-2.png),
[four bounces, accumulated](dx12-path-trace-live-smooth-final/river-path-4-still.png),
[cave](dx12-path-trace-cave-smooth-final/cave-path-4-still.png).

All runs used isolated profiles, a free cursor, visible FPS and muted SFX,
stream and voice audio. No player-facing options or strings changed. The
translation checker passed all 3,042 remake entries and dynamic-key coverage.
All eight native path shader binaries reproduced with DXC 1.9.2609.5.
Production source hashes match the exported runtime. Windows was exported
with the qualified template and approved icon; its EXE is byte-identical to
the previously icon-qualified export. The new PCK hashes are in [build.json](build.json).

## Diagnostics and remaining limits

Final native Vulkan tests emitted no validation errors. An initial version of
the synthetic uploader created a transfer-only image that Godot still gave an
image view; the fixture now adds sampling usage, and all three native runs
were repeated with validation enabled. Production target allocation did not
require a change.

The known Wine shutdown page fault recurred after the application's clean-exit
message in the updated frame-generation run, and in two saved-baseline runs:
read `0000000241BB6030` at `00006FFFFFC81448`. In-game assertions passed, but a
zero runner exit code does not make this a clean native-Windows qualification.
The exact diagnostics are retained beside each run. Baseline DXGI/EDID/SDR
warnings also remain. No shader compile or script errors occurred in the
recorded updated runs.

The integrator remains bounded path-traced lighting. Water still has its
separate reflection renderer; moving glossy paths, small emissive sources,
thin geometry and imperfect original material data can still produce noise
or seams. See the [integration document](../../integrations/path-tracing-experiment.md)
for the full limits and fixture commands. [summary.json](summary.json) lists
every recorded run, assertion count, expected baseline failure and shutdown
diagnostic. No release was published from this work.
