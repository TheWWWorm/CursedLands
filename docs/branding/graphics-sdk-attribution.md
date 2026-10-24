# Graphics SDK attribution

The local Windows preview has NVIDIA GeForce RTX, AMD FSR Upscaling
and AMD FSR Frame Generation artwork below the approved Cursed Lands logo and
title on the existing boot splash. No extra timed screen is introduced. The
approved master, application icons and ordinary/web splash are unchanged.

The Credits screen begins with the included SDKs' logos and attribution, then
continues with the original game credits and their existing scroll/exit behavior.
The added text is translated into English, Russian and German. Official brand
artwork and technology names are retained. There is no separate About dialog.

The exporter selects the splash and sets the attribution flags according to
package contents. They do not depend on the current GPU or selected graphics
settings. Ordinary source runs and builds without those package flags omit the
SDK credits. A package without AMD uses the NVIDIA-only splash.

## NVIDIA: local review, approval pending

The actual bundled DLSS license is
`licenses/NVIDIA/bin/x64/nvngx_dlss.license.txt` (March 14, 2024).
Its RTX supplement section 7.1(b) requires SDK attribution and marks on splash
screens, the About box if present, and game credits. Sections 7.2(c) and 7.3(b)
require written approval for proposed mark usage, including combination with
other content. Samples are to be submitted at least two weeks before intended
use; lack of a response is not approval.

The wording requires NVIDIA “Marks”, not explicitly a pictorial logo. Section
7.2(c) lists RTX word marks, so a text-only implementation may satisfy the
placement wording. That interpretation is not confirmed by NVIDIA, and using
text does not remove the written-approval clause. This review uses the requested
graphic badge and a separate DLSS technology name.

**This package is a local review build. Written approval has not been obtained.**
Placing a logo beneath the game logo is a proposed layout, not evidence that
NVIDIA has accepted the placement. No release notification, approval request,
email or public publication has been sent.

Before distributing the NVIDIA integration, obtain written approval for the
boot and credits placements. The review materials are the two generated
splashes, the EN/RU/DE credits captures, and the asset provenance manifest.
Any commercial release also needs the notification described in supplement
section 4. The publisher/developer details, release date and product link must
be supplied by the project owner.

Official references:

- [NVIDIA logo and brand guidelines](https://www.nvidia.com/en-us/about-nvidia/legal-info/logo-brand-usage/)
- [Official GeForce RTX logo](https://nvidianews.nvidia.com/file/geforcertx-logo-wht296273)
- [Commercial release notification form](https://developer.nvidia.com/sw-notification)

The full NGX, DLSS, Reflex and Streamline notices are retained in
`licenses/NVIDIA/`. The required source-code attribution is also in
`THIRD_PARTY_NOTICES.md`; translated explanatory copies appear in credits.

## AMD

The package preserves the complete SDK 2.3.0 `license.md` and
`3rdpartynotice.md` under `licenses/AMD-FidelityFX/`. This retains the copyright,
permission and disclaimer text with the signed binary SDK. The binary license
is not replaced by the MIT terms for individual SDK source files, or by the
game's Apache-2.0 license.

AMD's [FSR naming and logo guidance](https://gpuopen.com/amd-fsr-naming-guidelines/)
is recommended rather than mandatory. It recommends the white logos on dark
splash/about surfaces. The package uses the official Upscaling and Frame
Generation logos; it does not advertise Ray Regeneration, which is not included.
That FSR-specific page supplies these assets for game interfaces and states no
separate approval step. This supports the intended attribution use; it is not a
claim of unrestricted AMD trademark rights or AMD sponsorship. AMD's general
[media-library terms](https://www.amd.com/en/legal/terms-and-conditions/media-library.html)
concern products containing AMD processors and are not treated as a separate
license for this game.
The [pinned SDK license](https://raw.githubusercontent.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/v2.3.0/Kits/FidelityFX/docs/license.md)
is the source of the redistribution terms.

The Microsoft DirectX Agility runtime retains its own notices under
`licenses/Microsoft-DirectX/`.

## Reproduction

`graphics-sdk-assets.json` records the official download URLs and SHA-256
checksums. Source artwork is retained byte-for-byte. NVIDIA's downloaded PNG
contains an opaque white page around its badge. The splash compositor and
credits AtlasTexture display the complete badge region `(290, 278, 2420, 730)`,
omitting that white canvas. Badge pixels and proportions remain unchanged;
the layout supplies surrounding clear space. AMD artwork is resized with its
aspect ratio preserved.
These trademarks are excluded from the project's Apache-2.0 license.

Run `node tools/generate_branding.cjs --graphics-sdk` with `sharp` available to
regenerate the two experimental splash PNGs. `tools/build_fsr_preview.py --rtx-sdk /build/streamline-sdk`
selects the appropriate variant in its isolated export copy and records the
pending NVIDIA approval in `BUILD-INFO.json`.

## NRD restoration, 2026-10-24

Windows and Linux x86-64 previews also include NVIDIA NRD 4.18.0 REBLUR.
Their credits display the NVIDIA mark, a separate NRD attribution, source-code
notice and trademark notice whether path tracing is enabled or not. Linux does
not claim DLSS or AMD FidelityFX SDK support. The NRD license supplement 6.1(c)
requires marks and SDK attribution in credits; 6.3(b) requires prior written
approval for proposed mark use. This requirement remains pending for these
local review layouts. The DLSS splash placement is specific to Windows.

The native NRD binary and shaders are covered by `NATIVE_NRD_NOTICES.txt`;
NVIDIA DLSS/NGX/Reflex and Streamline retain their separate unmodified SDK
notices under `licenses/NVIDIA/`. Restoring these credits does not establish
NVIDIA approval or complete any commercial-release notification. Public
release is not part of this local preview task.

Pinned NRD terms: [NRD 4.18 license](https://github.com/NVIDIA-RTX/NRD/blob/v4.18.0/LICENSE.txt).
