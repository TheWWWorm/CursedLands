# RTX 30 package permanently withdrawn

The optional Windows RTX 30 package using `dlssg_for_sm86` was removed from
Cursed Lands 1.28.0 on 2026-10-24 because its redistribution rights were
unresolved. The project owner prohibited publishing it again.

Do not upload, mirror, bundle or republish this package or its modified NVIDIA
kernels, including in previews or drafts. The preparation tool and archive
recipe are disabled. Run `python3 tools/check_release_assets.py ASSET...` on
all proposed release artifacts before uploading. It rejects the mod's package
names, payload paths and build metadata, including inside renamed archives.

The mod's own MIT code does not relicense the NVIDIA-derived kernels, as
explained in its [third-party notices](https://github.com/sdli1995/dlssg_for_sm86/blob/0.4.0/THIRD_PARTY_NOTICES.txt).
The [historical validation](../validation/dlssg-sm86-2026-10-24.md) records local
technical tests; it does not establish distribution rights. Historical recipes
or successful test results must not be used to override this withdrawal.

The ordinary Windows build remains the download for RTX 30 hardware. This
withdrawal does not establish license clearance for the standard DLSS/NRD
integration; its separate attribution and approval requirements remain in
[SDK attribution](../branding/graphics-sdk-attribution.md).
