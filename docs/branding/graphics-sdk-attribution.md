# AMD FSR attribution

The FSR package displays the official AMD FSR Upscaling and AMD FSR Frame
Generation white lockups beneath the Cursed Lands title. Both keep their
original transparency and proportions, centered as a pair with clear spacing.
The approved dragon master and platform icons remain unchanged.

The same two marks appear in the credits with English, Russian and German
technology attribution, trademark attribution and a pointer to the complete
notices included with the package. Credits remain visible even when the
current device does not support an optional feature.

The artwork comes from AMD's
[FSR naming and branding guidelines](https://gpuopen.com/amd-fsr-naming-guidelines/),
which offer these marks for FSR integrations and describe the recommendations
as non-mandatory. This does not grant rights to unrelated AMD marks.
The files retain AMD's trademark rights. Original asset URLs and hashes are
in [the asset manifest](graphics-sdk-assets.json).

Regenerate the composition with `node tools/generate_branding.cjs --fsr`.
The export helper selects `splash-fsr.png` and sets the AMD attribution flag
in its isolated copy. Ordinary exports keep their normal splash.
The package includes the original SDK license and third-party notices under
`licenses/AMD-FidelityFX/`, and DirectX Agility notices under
`licenses/Microsoft-DirectX/`. Attribution does not replace these notices.
