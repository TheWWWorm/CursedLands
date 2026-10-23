# Cursed Lands 1.26.0 qualification

The exports use game tree `8a4372be6bc73647f158747950f68d49550a711e`, committed at `0158ff77335a485399067e74ce65c580d01fbf31`. It includes the local campaign/UI changes, LiA party inventory corrections and remote `dd12a31e` path-tracing changes. Later evidence and hosted-export commits do not change that game tree.

The [release record](../release-1.26.0-2026-10-24.json) separates build audits, runtime results, browser checks, publication and deployment. Source campaign qualification is in the [base campaign record](../base-campaign-checkpoints-2026-10-23.md) and [LiA inventory record](../lia-party-inventory-2026-10-24.md). The two previously failing native LiA references also pass twice against the exact integrated release game tree: [comparison report](integrated-native/report.json).

| Platform | Current package qualification |
| --- | --- |
| Linux x86-64 | 15 packaged configurations, 1,224 reported checks: quest bags, co-op/save transport, Kel and Shaina, difficulty/dialogue clocks, mods, shop/localization, village camera, shader progress and menu loading/return. Counts include overlapping loading configurations. |
| Windows x86-64 | 303 checks across eight Wine/VKD3D configurations: water/PT devices, moving geometry, lighting history, live tracing, five real worker save/load cycles and FSR recovery. [Results](windows-packaged-qualification.json). |
| Android ARM64 | Release manifest, code 60, existing app identity/certificate and native library hashes verified; no current device execution. |
| macOS universal | Archive, architectures, version, icon and scripts verified; unsigned, no target execution. |
| Browser | Fresh engine startup and actual published 1.25.0 cache upgrade passed; imported-data/save sentinels remain byte-identical. Both campaigns' public wiki controls pass in EN/RU/DE, including Back, reload and overflow checks. |

All **419 compiled scripts** match across the five exports. The Windows executable embeds the approved six-size icon and current version. Its code section matches the freshly linked corrected 20-patch engine template; [binary provenance](windows-package-provenance.json) distinguishes this cross-build from the separate native Windows source qualification. Android retains the established signing certificate and application ID. Original game data, player saves and private probes are excluded from the release packs.

The [native wiki index](native-wiki/index.json) records six additional packaged visual runs and 18 captures across both campaigns and EN/RU/DE. Shader-screen captures cover EN/RU/DE at 640×480 and 1280×720; representative Russian, German and real arena progress images were visually checked. Test profiles keep the cursor free, FPS visible and all audio muted. GPU work ran on isolated GPU Lab virtual displays with automatic GPU assignment.

## Publication and live deployment

[Version 1.26.0](https://github.com/TheWWWorm/CursedLands/releases/tag/v1.26.0) is public at tag commit `2cf57d305c014010206610a4653731417b50b5ac`. All six public downloads match their local SHA-256 digests; [publication receipt](publication.json). This post-publication evidence commit does not replace the tag or artifacts.

The [live deployment receipt](deployment.json) verifies 3,199 assets against that commit: every current changed hosted file since 1.25.0, the complete engine cache, all split WASM parts and reassembled files. Required isolation headers also pass. The six [deployed wiki scenarios](deployed-wiki/wiki-browser.json) cover both campaigns in EN/RU/DE, actual Cut content navigation, Back, reload and layout overflow; all six screenshots were reviewed. Unchanged wiki files outside that live scope were checked locally against the hosted manifest.

After publication, issues #61, #62, #90, #91, #92, #93, #97, #99, #100, #101 and #102 were closed as completed with `fixed in #1.26.0` and the release link. The [closure receipt](issue-closures.json) contains each comment URL and confirms that #29, #89, #94, #95, #96 and #98 remain open.

## Retained test setup diagnostics

The initial village camera fixture asserted modern follow while cold-start shader preparation still owned the input gate. Its diagnostic probe recorded `shader=true` and `blocked=true`. Waiting for actual readiness fixes the fixture; all 70 checks pass without a game change. The initial arena draw-order run used OpenGL, where its `CompositorEffect` counter stayed zero. The unchanged test passes all 27 checks using Vulkan. These original runs and their explicit replacements remain in the release record and `investigations/`; they are not reported as successful runs.

The initial browser wiki test looked for the page title inside the article after the frontend had moved it into a separate heading. Only that private test selector changed before the successful six-scenario rerun; its diagnostic is retained with the web validation evidence.

## Scope

Quest tests exercise prepared authored scenarios and native checkpoints, not every possible quest ordering or an uninterrupted manual campaign. Legacy saves retain their known live quest inventory; unrecorded historical party bags cannot be reconstructed. Windows runtime results here are under Wine/VKD3D, not native Windows. Browser checks establish engine startup/cache migration and wiki behavior, not a complete browser campaign. Audio checks observe requests, mixer state and routing while muted. Publication and live deployment were verified separately after upload; published tags and assets remain immutable.
