# PT travel continuity validation — 2026-10-28

The renderer starts replacements ahead of sustained camera travel, prepares them in bounded work slices, and publishes only a complete nearby scene. Opaque PT blending follows camera distance while retaining a separate geometry safety bound. DLSS Ray Reconstruction keeps motion history through continuous fast travel and changes to the nearby light list; genuine camera cuts, projection changes and abrupt global illumination still reset it.

## Failure and implementation

The E3 investigation reproduced two independent failures in the 1.33.0 renderer: a moving camera could outrun the retained PT scene and receive conventional shading until a replacement arrived, and repeated RR resets could temporarily erase fine soil detail during that uncovered travel. The PT option remained enabled. The earlier perspective wall-receiver fix is separate and remains intact.

- Start a predictive replacement after 4 m of sustained movement, instead of waiting for the ordinary 16 m recenter threshold. Look ahead by 64 movement steps, capped at 160 m. Isolated cuts use the exact camera pose.
- Validate predictions against the travelled segment. Cancel a distant prediction after an early stop or a departure from that segment. A complete predicted scene stays private until its center is within 32 m of the camera.
- Give live travel a 6 ms gather/build scheduling budget, with up to 9 ms of gathering for fast predictions over 64 m. Keep that gather budget while the same fast candidate is pending. Advance completed GPU resource phases in the remaining budget instead of inserting idle frames; remove the sixteen-BLAS-per-frame bottleneck for boosted builds. An indivisible native operation can exceed its scheduling slice; these are scheduling deadlines, not hard frame-time guarantees. Ordinary 1.5 ms builder calls retain their previous limits.
- Keep the 60–72 m quality fade centered on the eye. The independent geometry fade covers 84–96 m around the retained snapshot. Existing depth, normal, material and foreground rejection remain mandatory.
- Separate the RR view identity from strict local-light cache identity. Retain the stricter cache reset policy. Recognize both constant spatial steps and constant velocity with varying frame intervals. Preserve the last moving step across up to three duplicate presented poses, then forget it after a stop; jumps of 48 m or more remain cuts.

The fix changes shared rendering behavior, not a camera recording or trailer edit. It changes no terrain textures, save formats, gameplay rules, player defaults or visible strings.

## Regression contracts

The following cases are registered in `tools/regressions.json`:

| Case | Contract |
| --- | --- |
| `path_trace_travel_history` | 22 real controller-frame checks: 20/30/60 Hz travel, variable frame times, duplicate poses, stop/cut/projection/global-light discontinuities, and local-light membership with strict cache resets preserved. |
| `path_trace_coverage_handoff` | 6 rendered material checks: unchanged visible illumination across scene-center changes, with out-of-bounds and unrelated foreground rejection. |
| `path_trace_travel_coverage` | 9 checks on a fresh LiA gz3h 140 m route: same-frame camera/trace identity, active PT, complete near coverage by arrival, resource-failure checks and early-stop cancellation. |
| `path_trace_travel_night` | 10 checks on the elevated-to-close night route, including actual ground color before and after the held view. |
| `path_trace_travel_rr` | 14 checks on the doorway route at native 3840×2160 output / 1920×1080 DLSS input, including SDK evaluations, reset count and fine-ground contrast. |
| `path_trace_travel_rr_night` | 15 checks combining actual 4K RR with the night lighting comparison. |
| `path_trace_light_history` | Register the existing 52-check responsive/progressive lighting test with its required `--ei-pt-tuning` switch. No assertions were relaxed. |

The camera fixtures change pose at `SceneTree.process_frame`, before the priority-101 controller, and capture after rendering. They assert that the queued trace and camera use the same pose. Earlier diagnostic fixtures that changed the camera directly from a draw callback could manufacture a raster/trace mismatch; those captures are not the final acceptance evidence.

The original release fails the new motion-history, receiver-blend and travel regressions. An intermediate implementation also fails the duplicate-pose test and the stricter night arrival/color checks. Retained logs distinguish those failures from the final results.

## Validation record

Detailed baseline/fixed results, exact commands, script and executable/PCK hashes, SDK state and selected images are retained in the workspace at `local/validation/pt-travel-fix-20261028/`. Its `REPORT.md` is the acceptance record. Tests use the qualified packaged renderer; a stock editor is used only for CPU imports and PCK exports.

Related coverage includes loading/recentering, history handoff, raw RR presentation, live native RR, guide matching, topology budgets, program reuse, resource staging/retirement, water bounds, grass/cover/material receivers, and the 97-check perspective wall regression. The regression-runner unit suite is also run. Actual native RR cases use standard Proton GE11-11 and NVIDIA RR/SR on GPU Lab, with automatic GPU assignment, a single exclusively locked disposable prefix and isolated muted/FPS/free-cursor profiles.

No fresh original-game Wine comparison applies: the original has no PT scene streaming, DLSS or Ray Reconstruction counterpart. Original LiA terrain data is the shared reference input and is not modified. Fresh gz3h reproductions use disc-input data and are not exact replays of the supplied multiplayer save. Available RTX 3090/3090 Ti hardware exercises standard RR/SR with frame generation disabled; the user's 4090 Laptop/FG path is not certified by these runs. Functional 4K tests are not a 60 fps performance claim.

No release or remote update is part of this change.
