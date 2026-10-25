# RTXPT 1.9 ideas applied to Cursed Lands

Research and validation: 25 October 2026. Started from local integration
`42e3365f`, retaining the accepted Dar Leanos, first-person lighting, motion,
weather, and NRD changes.

NVIDIA reports approximately 20% higher performance for its own RTXPT 1.9
sample, combining several optimizations. Our renderer is a separate Godot
Vulkan/DX12 implementation. Updating an SDK version does not transfer that
result to this game. This change implements sparse scene-record uploads and
avoids unnecessary TLAS builds; it does not integrate the RTXPT renderer.

Primary references:

- [RTXPT 1.9 release notes](https://github.com/NVIDIA-RTX/RTXPT/releases/tag/v.1.9.0)
- [RTXPT 1.9 pipeline design](https://github.com/NVIDIA-RTX/RTXPT/blob/v.1.9.0/Docs/Design.md)

## Applicability

| RTXPT change | Cursed Lands assessment |
| --- | --- |
| Sparse GPU updates and less CPU scene work | Implemented here for motion and lighting-offset records, plus redundant TLAS builds. Existing source caching and motion packing remain intact. |
| GPU-generated TLAS instance descriptors | Requires extending the patched engine's Vulkan and DX12 APIs. The current API consumes CPU instance objects. The present change does not claim GPU-generated TLAS descriptors. |
| Async overlap with DLSS Ray Reconstruction | Requires render-queue scheduling, resource lifetime/synchronization work, and an RR integration. Our current PT reconstruction uses NRD/custom filtering; RTXPT's new async path is DX12-specific. |
| SHaRC radiance caching | A promising larger integration for indirect light: cache update/query passes and early path termination, with validation for moving lights, weather, dynamic actors, streaming, caves, and light leaks. RTXPT documents bias and delayed response to lighting changes. It is not enabled here. |
| Sub-one-sample-per-pixel rendering | Requires reconstruction that explicitly understands missing samples. Simply skipping rays in the current integrator would contaminate lighting, hit distances, and temporal history. Existing resolution scaling stays intact. |
| NEE-AT and emissive light LODs | Potentially useful for much larger emissive sets, but not a direct replacement for our bounded local-light and emitter sampling. Requires new light structures, feedback, and statistical tests. |
| NRD update | Our native integration already uses NRD 4.18; RTXPT 1.9 lists 4.17.3. No downgrade or SDK replacement is needed. |
| Other SDK, SER, opacity-micromap and bindless changes | Require engine/backend qualification and are outside this change. No NVIDIA source or binary package was imported. |

## Implemented behavior

Previously, two changed placements at opposite ends of 8,192 stable IDs caused
a 786,432-byte motion upload and a 131,072-byte lighting-offset upload. The
unchanged records between them were copied into staging memory and uploaded
again. The new path sends 192 and 32 bytes respectively.

Adjacent records stay in one upload. Gaps of at most 32 KiB are coalesced, and
each buffer uses at most eight uploads. If there are more eligible gaps, the
seven largest are excluded. Dense motion has a fast path that avoids scanning
individual gaps. Lighting offsets are only 16 bytes per record: batches of
128 or more placement changes retain the previous min/max upload policy,
avoiding the measured cost of collecting every changed offset ID. The threshold was measured: a 4 KiB prototype made a
fragmented workload slower by issuing too many small offset uploads; 32 KiB
retains the useful transfer reduction without that observed overhead.

The shared water/scene/PT device now skips TLAS rebuilding for identical
transforms and masks, including changes that only adjust a first-person
lighting origin. Fully masked placements retain their current transforms
without rebuilding the active TLAS. Moving visible objects, hide/reveal
transitions, and posed geometry still rebuild it. Reveal still creates a
previously unused BLAS and uses the latest hidden transform.

The shader sources, sampling budget, material reconstruction, output formats,
history rules, and player settings are unchanged. Sparse records include both
current motion and the previous frame's pending resets. Deformation and
scene-handoff rejection remain authoritative, and any failed upload prevents
publication of the partial update.

## Measured cost

The final Vulkan comparison used one RTX 3090 in GPU Lab heavy job
`1c5367f437184d5e`. Each workload alternated previous/new/new/previous uploads
in the same executable, with 40 warm-up and 100 measured updates per block.
The values below average the two block medians. Timings include render-thread
motion packing and motion/lighting-offset buffer submission, not full frame
rendering or GPU execution time.

| Changed placements | Previous CPU time | New CPU time | Previous bytes/update | New bytes/update |
| --- | ---: | ---: | ---: | ---: |
| Two distant IDs | 100.0 µs | 31.5 µs | 917,504 | 224 |
| 1,024 adjacent IDs | 2,635.5 µs | 2,612.5 µs | 114,688 | 114,688 |
| Sixteen separated groups | 139.0 µs | 130.5 µs | 840,112 | 504,784 |

The sparse two-object case reduces this component's median CPU time by about
69%. The absolute saving is about 70 µs; this is not a 69% or 20% game-FPS
claim. Dense and fragmented results are close enough that smaller timing
differences should not be generalized beyond this measurement. No matched
whole-game before/after FPS measurement is claimed.

## Regression evidence

The registered `path_trace_sparse_updates` fixture exercises real GPU buffers
and acceleration structures. It checks byte-for-byte readback across 8,192
slots, dense and fragmented uploads, bounded API calls, stopping/restarting,
deformation, handoff rejection, hidden movement, reveal/hide, lighting-only
updates, and failure of the second sparse upload. It fails nine assertions on
the previous behavior and passes all 44 on both Vulkan and DX12/Wine.

The baseline export contains only pass-through instrumentation around the old
upload and TLAS calls, so the fixture can count the actual work without
changing it. The benchmark's full-span reference likewise uses the previous
upload policy and original offset min/max bookkeeping with the same final
build and all the same records.

There are 812 passing GPU assertions across the retained Vulkan and DX12/Wine
receipts, plus 16 checks in the final benchmark and 23 CPU tests for the
qualification runner. The Dar Leanos first-person route passes all 54 checks.
Related validation covers rigid motion through ID 8191, previous motion-packing
regressions, direct moving shadows, scene handoff, NRD, first-person body
illumination, water and scene RT, and lifecycle/failure handling. The existing
water device fixture now actually moves its instance on resize, preserving
its intended second-TLAS-build barrier check after no-op builds are skipped.
The body-lighting fixture now disposes its final GPU device explicitly; the
final Vulkan and DX12 runs pass all 14 assertions without leaked-RID warnings.

The lifecycle fixture exposed a pre-existing stale expectation: it allowed 21
images, while direct-light reconstruction introduced in `18b58726` owns another
12 even with NRD disabled. The baseline fails the same assertion on both APIs;
the diagnostic records exactly 33 current images, no missing images, and no
unowned images. The updated guard checks the exact six pool sizes
`[7, 8, 4, 2, 8, 4]` and exact live/current resource membership. It retains the
zero-live-image retirement checks and detects both missing targets and leaked
old targets, rather than merely relaxing a count.

See the [machine-readable evidence](../validation/rtxpt-sparse-2026-10-25/summary.json)
for final results, source/runtime hashes, failed controls, and benchmark data.
The first test-launch attempt encountered disk exhaustion; its incomplete
checks were rerun. No incomplete run is counted as a pass.

An original-game Wine comparison is inapplicable to these remake-specific
Godot GPU buffers and hardware-PT acceleration structures. No original
gameplay, authored material, or lighting algorithm was changed. Wine coverage
here executes the remake's Windows DX12 path; it does not certify native
Windows driver performance or other GPU vendors.

## Reproduction

Use the registered `path_trace_sparse_updates` case in
`tools/check_regressions.py`, or `--suite sparse_updates` in
`tools/tests/run_path_trace_qualification.py`. The latter includes it in
`full`. Run `--suite sparse_performance` separately in a GPU Lab heavy job.
Use freshly exported packs from the intended source and the normal isolated
profile, display, and device checks in [PT qualification](../path-tracing-qualification.md).

Local runtime bundles, profiles and complete logs are retained under
`/home/llm2x/Documents/EI/local/scratchpad/pt-rtxpt-20261025`.
No publication or remote update is part of this change.
