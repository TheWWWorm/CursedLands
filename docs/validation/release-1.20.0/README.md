# Cursed Lands 1.20.0 validation

Gameplay: 279 passing programs, 3 failing programs, 0 setup/runtime errors; 237811 assertions, 1384 failing assertions.

Original executable: all 594 bounded scenarios match across 1,288 observations. This is separate from the remake regression suite.

## Remaining failures

- `effects/footprint_surface`: 686 of 688 assertions fail (failed).
- `effects/footprint_surface_enhanced`: 686 of 688 assertions fail (failed).
- `effects/running_footprints`: 12 of 15 assertions fail (failed).

The three footprint programs exercise the missing OpenGL campaign decal path. Issue #29 stays open. Initial fixture/timing failures and all retries remain in `gameplay/results.json` and `gameplay/logs.zip`.

## Rendering and release scope

The image test reproduced Arena snow self-shadowing in the old package. The final package is checked at all four shadow qualities on OpenGL, DX12 and Vulkan, with separate assertions that cast shadows remain visible. Before/after captures are in `screenshots/`. FSR and formula-mod campaign checks use the ordinary Windows executable and profile.

The only production-script change after the broad integrated run is `src/ui/arena_pve_field.gdc`; the final exports have identical sets of 383 compiled scripts across all five platforms. See `source-delta.json` for that boundary.

Windows execution uses Wine/VKD3D on an RTX 3090. Native Windows, FSR 4 hardware, native macOS/Android runs and long-session image quality are not qualified. Existing saves and original game data are not bundled.

Browser checks cover a fresh launch and a 1.19.0 service-worker upgrade retaining IndexedDB. Cloudflare live receipts are recorded after publication.
