# Campaign issues #28 and #29 — 2026-10-18

## Outcome

[#28](https://github.com/TheWWWorm/CursedLands/issues/28) is reproduced and fixed in the local development build. A quiet load/join snapshot restored the stance flags but skipped the animation update when the incoming action was already `idle`. A paused tree could therefore keep the freshly constructed standing pose indefinitely. Quiet steady actions now select and evaluate their saved posture immediately, without a stance or movement-start transition and without advancing simulation time. The existing corpse restoration path is preserved.

[#29](https://github.com/TheWWWorm/CursedLands/issues/29) remains unresolved. The attached recording shows ordinary footprints on the dry Gipat village plaza. Footprint clipping was not reproduced on this machine in the published 1.16.0 Linux build or the current preview. No footprint-rendering change or issue closure is claimed.

## Evidence and checks

The published Linux archive was downloaded from release `v1.16.0` and verified against its published `SHA256SUMS.txt`: `1f3f12631a9d5a4c2e6befbd7972f39f100ad8f47900c371029e18897971fd88`.

| Check | Result |
| --- | --- |
| Quiet pose fixture on published 1.16.0 | 42 checks, 6 failures: prone/kneeling idle pose and unwanted walking-start sequences |
| Same fixture on updated pack | 42 checks, 0 failures, including corpse-pose preservation |
| Actual paused save/load through private solo worker | 31 checks, 0 failures; prone, kneeling, standing, saved pause and speed |
| Actual paused save/load in process | 30 checks, 0 failures |
| Rendered private-worker save/load | 37 checks, 0 failures; screenshots after the loading cover closes and before manual animation evaluation |
| Snapshot recovery | 18 checks, 0 failures |
| Direct attack/stance regression | 39 checks, 0 failures |
| Rendered autochess round lifecycle | 695 checks, 0 failures; three rounds, worker replicas, pause at 2×, retained terrain and retired world cleanup |
| Original village terrain: 49 footprints, 14 camera angles | 687 checks, 0 failures |
| Same terrain with authored walking surfaces loaded | 688 checks, 0 failures |
| Enhanced terrain, materials, soft-ground and ground-contact options | 688 checks, 0 failures |
| Native running footfalls, 1× and 2×, current pack | 15 checks, 0 failures; 93 generated footprints |
| Same running fixture, published 1.16.0 | 15 checks, 0 failures; 93 generated footprints |

The running fixture uses the original hero's running animation and actual footfall extraction on `basegipat` / `basecam`. It moves the hero and following camera around dry soil with animation increments of 1/18 simulated second, doubled for 2×. This is a controlled low-cadence visual test, not a benchmark or a replay of the reporter's inputs. Twelve image comparisons examined 248 visible, unfaded mark observations across both speeds; all remained visible. Scenery is hidden for the pixel comparisons while its authored walking surfaces remain loaded; marks obscured by the hero or undergoing their normal end-of-life fade are excluded. The tested plaza's ground row retains the original 600-tick lifetime and 150-tick fade.

Testing used Linux, an RTX 3090, Vulkan Forward+ and the safe rendering thread. It does not establish behavior on the reporter's GPU, their graphics/anti-aliasing settings or their saved game. Those details and an affected save would be the useful next evidence for #29.

Attempting the **rendered** autochess UI fixture with `--headless` caused an engine segmentation fault in both the unchanged second preview and the candidate. The same fixture completed with a display. These headless attempts are retained in the evidence directory as failures, not counted as passing validation. The actual headless solo authorities used by the rendered tests and campaign save/load tests completed normally. This existing UI-fixture/headless failure was not changed in this follow-up.

## Saved artifacts

Logs, numeric results, screenshots and the package manifest are in [campaign-issues-28-29-20261018](campaign-issues-28-29-20261018/). Example captures:

- [Prone hero after a paused load](campaign-issues-28-29-20261018/paused-load-gait-0.png)
- [Kneeling hero after a paused load](campaign-issues-28-29-20261018/paused-load-gait-1.png)
- [Running footprint trail at 2×](campaign-issues-28-29-20261018/running-footprints-2x.png)

`CursedLands-autochess-preview3-windows-20261018.zip` is an unpublished local follow-up to the second preview. It contains the same autochess changes plus the fix for #28. Its Windows PCK is byte-identical to the tested Linux PCK. Archive CRC verification passed; Windows execution was not tested here. No release version, public tag, published artifact or GitHub issue state was changed.

- Archive bytes: `45,961,164`
- Archive SHA-256: `231f31158c8bbef950c5a8b0b56d39929d48506aede423bdeffe6b99b8387f98`
- Tested PCK SHA-256: `b20001cfef2df59a7b580a16fccbe9ec255e1eb5fddbdc7bf591f23a7b0f10b9`

The performance measurements and remaining limitations from [the second preview](autochess-preview2-20261018.md) remain the previous performance evidence. This follow-up did not repeat the full FPS benchmark matrix and makes no new performance claim.
