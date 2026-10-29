# PT failure fixes — 2026-10-29

The incoming PT completion report recorded nine failures in 80 rendered cases on a native Windows RTX 4090 laptop. This follow-up investigates the affected behaviour on GPU Lab with RTX 3090-class GPUs, driver 580.178.04, native Linux Vulkan and the Windows build under GE-Proton 11-11 / VKD3D. It does not replace native Windows qualification.

## Confirmed failures and regressions

- The new terrain closest-hit shader crashed the NVIDIA Vulkan pipeline compiler with exit 139. A minimal pipeline probe isolated the dynamically indexed private arrays in the four-entry cliff-colour memo. Four scalar entries preserve the same memoization and avoid the compiler crash. `path_trace_programs` fails against the unfixed PCK and passes all 41 pipeline checks after the fix; all 120 terrain-reference comparisons also pass. The ordinary, RTXDI and SHaRC shader families were rebuilt with pinned DXC 1.9.2609.5, and their manifests were checked. Three other shader families had stale builder hashes; their 24 rebuilt outputs were byte-identical and only metadata changed.
- Native capture setup could remain maximized/fullscreen at 2880×1800 despite a 3840×2160 request. Windows ignores size changes in those states. `capture_window` first leaves that state in a framed smaller window, then waits for native window, viewport and requested size to agree. `capture_window_extent` passes 21 checks across 720p, 1440p and 4K, including a deferred startup resize. Existing option and traversal size assertions are unchanged.
- A zero-monitor display topology previously reached per-screen queries. `screen_topology` reproduced this with a Windows-like backend and now passes seven checks, including monitor removal and teardown. The window placement path also skips per-screen work when enumeration is empty.
- The river fixture received a 1/64-metre rounded position on a closed cell boundary. The authored terrain permits the authority's position less than 4 mm away in the adjacent cell. The route selector now probes only within that rounding interval and restores the replica synchronously before returning. It can also select a 1.5–2 m leg when all longer candidates are obstructed. `path_trace_route_origin` failed before both fixes and passes 15 checks afterward, preserving terrain, body, exit and real-movement assertions and rejecting genuinely closed terrain. Production navigation is unchanged.
- Night travel reproduced a colour difference of 0.148321 between the moving and held endpoint, above the unchanged 0.04 limit. The replacement became ready at frame 60, too late for that captured image. Fast-travel gathering now reserves 16 ms (20 ms with RR), leaving time for staged resources, BLAS work and the first presented result; normal movement and the GPU build slice are unchanged. The same Linux route promotes at frame 49 and measures 0.001996. Day travel also passes, as do the 22 history-classifier checks and 15 native CPU-cache checks.

## Windows build and frame generation

The integrated Proton suite passes capture extent (21), all native pipelines (41), water options (28), RR options (50), ReSTIR options (59), transmission options (56), RR day travel (14), RR night travel (15), and 4K snow traversal (49). Option cases exercise EN/RU/DE. A separate frame-generation toggle/resize test passes 68 checks, including 180 game presents producing 360 SDK presents. Snow traversal also verifies actual generated presentation.

These FG checks use an owner-authorized local compatibility setup. That test-only setup is excluded from release construction and distribution. Standard release packages use only the approved vendor runtime files.

## Comparison and evidence

The original game has no path-tracing, DLSS or Godot window-management counterpart. Original Wine comparison is therefore inapplicable to these fixes. The river change affects only the test route selector; its checks use the authored map and the production snapshot, navigation and body-sweep logic.

Compact logs, red/green results, shader provenance and selected captures are retained in the workstation's `local/validation/pt-release-20261029`. Final package acceptance and platform limitations belong to the release validation record. An initial CPU-cache invocation used the stock editor, which lacks the custom PT backend; its corrected packaged run passes. No assertion was removed to obtain these results.
