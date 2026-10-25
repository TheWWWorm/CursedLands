# PT material filtering and third-person validation — 2026-10-24

Primary rays previously left their texture cone at zero, so closest-hit always
sampled base colour and equipment roughness/metalness at LOD 0. At reduced trace
resolutions, a single lighting pixel could represent many material texels while
sampling only one sharp point. Small camera or actor movements changed the
represented material instead of retaining its filtered average.

The closest-hit shader now derives the primary footprint from the actual trace
dimensions and camera projection. Perspective footprints grow with view depth;
orthographic footprints remain independent of depth. Projection onto the actual
triangle accounts for foreshortening, including continuation cones. Magnified
materials retain LOD 0. Raster colour sampling, sharp-character settings, ray
counts and DLSS settings are unchanged.

All 18 DXIL/SPIR-V outputs were rebuilt and reproduced with the pinned DXC.
The ordinary, terrain and terrain-transition closest-hit variants contain the
change. The existing Windows engine fixes from main at `bab580bd` remain included.

## Validation

The paired JSON records exact runtime and fixture hashes. The final exported
packs passed 262 checks:

| Suite | Vulkan | Windows DX12 |
| --- | ---: | ---: |
| Subpixel material filtering | 9 | 9 |
| Equipment material maps | 16 | 16 |
| Authored surface detail | 47 | 47 |
| Material receiver boundaries | 6 | 6 |
| NRD motion and rejection | 42 | 42 |
| Actual third-person hero | 8 | 11 with DLSS SR |
| Matched performance fixture | 3 | — |

The filtering fixture uses a known alternating material pattern, four projection
and viewing-angle cases, and 16 subtexel camera positions per case. The preceding
pack fails seven of nine checks: decoded metalness spans as much as 1.0 during
motion. Both corrected backends retain the same decoded value throughout every
sequence, with maximum error 0.01613 against the independently known 0.5 average
(within the material guide's quantization).

The live check uses the original Gipat map and original hero, viewed from behind
at dusk. Display size is 3840×2160, raster scale 50%, PT Low at 960×540 and two
bounces. Across 144 held, walking and panning frames, PT and NRD remain active,
articulated geometry updates, and ordinary daylight retains temporal history.
The Windows test confirms continued SDK evaluation of DLSS Performance with no
SDK error. Eight subsequent animated-back coverage captures on each backend
contain over 5,000 accepted samples and zero classified rejects per capture.

The first coverage diagnostic used red for rejection and inadvertently counted
warm skin/cloth outside the instrumented torso. Green/magenta classification
corrects the fixture; both successful reruns use exactly the same runtime packs.
This was a measurement correction, not a further renderer change.

An exclusive GPU Lab job compared both packs sequentially on the same RTX 3090.
In the frozen river benchmark at 1280×720, two bounces and Low PT, two rounds of
90 samples measured PT GPU medians of 0.848/0.856 ms before and 0.848/0.848 ms
after. No meaningful GPU regression was measured in that scene. Readbacks and
shader compilation are excluded from the benchmark; live screenshots are not
performance measurements.

All graphical runs used GPU Lab with automatic device assignment. Tests used
isolated profiles with a free cursor, FPS display and muted game audio.

## Scope

Windows testing ran the actual Windows executable and original DLSS SR SDK
under Proton/VKD3D on Linux. Native Windows and DLSS frame generation were not
exercised locally. This change corrects a demonstrated material-sampling source
of shimmer; it does not establish that every artifact in the recordings is gone.
The earlier material/effect and lighting fixes are retained. This is a local
development package, not a new published release.
