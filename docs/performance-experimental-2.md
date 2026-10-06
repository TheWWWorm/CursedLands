# Experimental 2 CPU checkpoint

This release adds the default reactive AI scheduler, fewer repeated AI/party/quest-light reads, typed footprint bookkeeping, native navigation-grid construction on Windows/Linux, and a local cache of derived foliage masks. It preserves the fixes and patched desktop animation runtime from Experimental 1.

The optional **Distant AI (experimental)** setting remains off. It is a separate approximation experiment; none of the measurements below enable it. The aim is to make normal game systems efficient enough that this option becomes unnecessary.

## Measured gameplay

Comparison against `v1.0.3-experimental.1` (`969bc7a`), using the same desktop engine binary. Linux/X11, Godot 4.7, Ryzen 9 5950X, RTX 3090, 1280×720, native render scale. The River and Islands (`gz7g`) fixture has 239 simulated units, a protected hero and a stationary starting camera. Each run warms for 180 simulation ticks, then measures 20 seconds. Two runs per variant and speed were interleaved, with isolated settings and no concurrent game engines.

| Speed | Experimental 1 FPS | Experimental 2 FPS | Mean change | Main-thread CPU per frame |
| --- | ---: | ---: | ---: | --- |
| Normal | 106.8–112.1 (mean 109.4) | 123.9–124.1 (mean 124.0) | +13.3% | 8.58 → 7.56 ms |
| Double | 44.9–51.4 (mean 48.1) | 62.0–65.2 (mean 63.6) | +32.2% | 19.44 → 14.59 ms |

Mean per-run 95th-percentile frame time improved from 20.14 to 17.34 ms at normal speed and from 30.38 to 24.74 ms at double speed. These are uncapped measurements of this starting scene, not a promise for every map, battle or device. Real-time ambient histories vary, and host load is not fully controlled. An uncapped CPU-bound game may continue using a full core while delivering more frames.

Individual runs still contain large frame-time spikes, up to approximately 322 ms in this candidate and 346 ms in the baseline. Crowded navigation and repeated reachability/path requests remain the next performance target. This checkpoint does not claim to solve dense-combat stalls or add multithreaded simulation.

## Validation and behavior

- Native/script activity results and wake-up guards: 7,975 checks per implementation. Real-map patrol, stealth and reaction scenarios: 22 checks per implementation.
- AI read semantics: 57,613 checks. Spatial queries: 38,611. Native perception queries: 5,762. Party/footprint behavior: 10,269.
- Navigation construction: 3,544 synthetic checks and complete array comparisons across three real maps, including River and Islands (231 checks). Foliage cache content, invalidation and corruption: 32 checks.
- Deferred animation: 134,357 pose/morph/clock assertions on the patched runtime and again on the stock engine fallback. Timeline safety: 5,294. Queued image/font rendering: 4 checks and 240 rendered font frames.
- Saved game assertions pass, including reconstruction of derived activity state. Buff counters pass command/save and real ENet checks; corpse timing/history passes body/save and ENet checks. These bounded fixtures are not a full campaign or a separate-process/WAN co-op playthrough.
- With the new scheduler disabled, a 460-tick comparison with Experimental 1 matches normalized gameplay state and both random streams at all three checkpoints (79 strikes and 31 hits during the fight phase). Enabled scheduling deliberately avoids otherwise empty AI refreshes, so ambient random-number consumption and trajectories may change. Core combat rules remain unchanged.

The existing save fixture still reports four leaked ObjectDB instances and one resource at shutdown, as in its prior control. The options fixture also has teardown warnings. Normal runtime smoke checks and focused behavior tests are assessed separately; this is not a claim that the entire repository test suite is clean.

All five release packages passed content/license audits, and the Android APK uses the same signing certificate as Experimental 1 with version code 13. The packaged Linux executable loaded the opening campaign, saved an isolated autosave and exited with no errors or warnings.

Linux is the runtime-tested platform. Windows native code is cross-compiled; Windows, macOS and Android device playtests remain outstanding. macOS, Android and Web retain their script fallbacks and stock engine templates, so the desktop FPS gain must not be assumed for them.

## Diagnostics

`-- --ei-legacy-ai` disables reactive scheduling for comparison. `-- --ei-script-activity` selects its script implementation. `-- --ei-eager-poses` disables hidden-pose deferral. These switches are for diagnosis; normal play needs no performance option enabled.

See [AI activity scheduling](ai_activity.md) for the behavior and wake-up contract. The save format and co-op protocol are unchanged; use this same experimental version on all co-op participants.
