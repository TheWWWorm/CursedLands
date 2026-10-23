# Unmapped material control on GPU 1

The remaining authored-material performance control is qualified on physical
GPU 1, an RTX 3090 Ti. Both native Vulkan and the Windows DX12 export through
Wine/VKD3D complete 32 measurement blocks and 66 assertions: 132 passing checks
in total, with both processes exiting normally. This closes the pending control
in the [authored-lighting report](../path-tracing-authored-lighting-2026-10-23/README.md).

The comparison measures the incremental cost of the new closest-hit program
in one frozen scene where authored prop maps are disabled. The largest median
frame increase is 0.229 ms, or 3.2%, in four-bounce DX12 Medium. Native Vulkan
is effectively unchanged. The aggregated median PT GPU time increases by at
most 0.007 ms. Small negative deltas do not establish a general speedup.

## Results

Each value is the median of four per-pass medians. Each pass samples 120 frames
after 40 warmup frames. The 1280×720 client traces Medium at 960×540, two samples
per pixel, and High at 1280×720, four samples per pixel. Bounces are continuation
bounces. Reference and current programs alternate in both orders.

| Backend | Bounces | Quality | PT GPU ms, reference → current | Frame ms, reference → current |
| --- | ---: | --- | ---: | ---: |
| Vulkan | 2 | Medium | 3.065 → 3.039 | 4.773 → 4.787 |
| Vulkan | 2 | High | 10.832 → 10.579 | 11.666 → 11.466 |
| Vulkan | 4 | Medium | 3.423 → 3.429 | 5.175 → 5.117 |
| Vulkan | 4 | High | 11.579 → 11.509 | 12.467 → 12.414 |
| DX12 through Wine | 2 | Medium | 4.259 → 4.094 | 7.705 → 7.464 |
| DX12 through Wine | 2 | High | 14.918 → 14.439 | 16.272 → 15.786 |
| DX12 through Wine | 4 | Medium | 4.812 → 4.599 | 7.235 → 7.463 |
| DX12 through Wine | 4 | High | 16.155 → 15.510 | 17.461 → 16.825 |

[Performance data](performance.json) retains all per-pass medians, including
controller CPU measurements. [Vulkan](vulkan-measurements.json) and
[DX12](dx12-measurements.json) retain every block's sample counts, p95 values,
timestamps, GPU stages and scene statistics. All blocks contain 120 GPU samples.
The PT interval includes ray dispatch, reconstruction and copies. Its delta
cannot be attributed solely to execution of the dormant material branch.

This GPU differs from the RTX 3090 used for earlier lighting and mapped-prop
comparisons. Keep their absolute timings separate. The earlier mapped-prop
costs remain approximately +0.20 ms PT on Vulkan and +0.65 ms through DX12/Wine
in that representative prop scene. This new control does not measure loading
maps, shading mapped surfaces or the cost of expanding material coverage.

## Comparison contract

The frozen river retains terrain detail, equipment/material support and the
same current scene collector. The fixture disables only authored prop maps
before snapshot collection and asserts that no geometry has a detail layer.
Every block retains 1,285 geometries, 1,420 instances and 116,008 triangles,
with zero instance or pose updates. Quality and sample counts match the table.

The saved pre-authored-prop library matches commit `9a3a93ec`, including every
compiled stage hash. It and the current library use the same compiler and
builder. All ray-generation, miss and any-hit binaries are byte-identical.
The closest-hit source difference is the authored-detail branch and its normal
helper. Switching programs preserves the acceleration structures, rebinds the
requested shader and invalidates history symmetrically before warmup.
[Source and export hashes](source-and-exports.json) identify the exact inputs.
The exports and runtime sources still match the authored-lighting checkpoint
at commit `6b4e20e2`; no production change was needed for this qualification.

The fixture's phrase “identical … images” refers to shared output resources.
There is no pixel-equality assertion or synchronized random sample sequence.
This is a controlled performance comparison of one frozen view with hidden
units, rather than a full-game FPS guarantee. Native Windows, other GPU vendors,
dynamic gameplay and additional material atlases require their own evaluation.

## Device isolation and display

Both engine logs and measurement files identify **NVIDIA GeForce RTX 3090 Ti**.
The physical device is index 1, PCI `00000000:0A:00.0`, driver `580.178.04`.
A private Xorg server used `BusID "PCI:10:0:0"`, disabled automatic input/GPU
binding, and restricted device resets to that PCI device. It used a private
authorization cookie, no TCP listener, no desktop compositor and no VT switch.
The ordinary desktop and other applications remained running.

The working display uses NVIDIA's `UseDisplayDevice "None"` and
`AllowEmptyInitialConfiguration`, with a 1920×1080 virtual framebuffer and an
explicit RandR monitor. NVIDIA documents the no-display configuration in its
[X configuration reference](https://download.nvidia.com/XFree86/Linux-x86_64/580.95.05/README/xconfigoptions.html).
An attempted forced 60 Hz output was refused because the second server could
not acquire modesetting permission; it was reverted without altering the
main desktop configuration.

**Expected Vulkan startup diagnostic:** Godot reports that it cannot obtain
the screen refresh rate because NoScanout has no active CRTC mode. The inspected
engine path returns `-1`; startup diagnostics record an unknown rate. The test
explicitly disables VSync and sets `Engine.max_fps = 0` before sampling.
This diagnostic is retained in [run records](runs.json), with no unexpected
errors or failed assertions. DX12 exits with no `ERROR:` lines; Wine/DXGI still
reports its virtual-monitor fallback and usual capability warnings. Neither
backend is described as a diagnostic-free physical-display run.

[GPU observations](gpu-observations.json) align one-second utilization, clock,
power and temperature samples with all measurement blocks. The complete
anonymized [Vulkan telemetry](vulkan-telemetry.jsonl) and
[DX12 telemetry](dx12-telemetry.jsonl) are also retained. The resident compute
client occupied about 7.1 GiB, and other clients retained small GPU allocations.
No unrelated client reported positive GPU or memory activity in the observations.
Unreported (`-`) utilization fields and one-second sampling cannot prove zero
instantaneous interference. The private display's own activity is recorded
separately from the benchmark.
CPU workloads and GPU clocks were not locked; frame-time deltas also include
scheduling variation. The interleaved passes and recorded per-pass values
provide context for the small observed differences.

The initial discovery run changed the monitor configuration while running and
is excluded. Previously contended GPU 0 measurements remain excluded. The
private Xorg server was stopped after testing, its authorization cookie was
removed, and GPU 1 returned to 0% utilization with its prior resident clients
intact.

All tests used isolated profiles with cursor confinement off, FPS visible and
all audio volumes zero. No player settings, strings, release versions or
published artifacts changed.
