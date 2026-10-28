# Handoff: Direct3D 12 menu deadlock fix

Prepared on the Windows test machine (RTX 4090 Laptop GPU) on 2026-10-28 for the
integration machine. Branch: `fix/d3d12-temporal-shader-deadlock`, based on
`72a79ab8` (1.34.0 release state). Read [README.md](README.md) first.

## What the branch contains

| File | Purpose |
|---|---|
| `engine_patches/godot-4.7/temporal-shader-preparation.patch` | Engine fix, 24th Windows patch after `dlss-ray-reconstruction.patch` |
| `engine_patches/godot-4.7/README.md` | Recipe entry for the patch |
| `tools/run_native_d3d12_cold_start.ps1` | Native Windows regression runner |
| `tools/tests/d3d12_cold_menu_start.gd` | Its fixture (`--tool`, uses `Main.open_menu()`) |
| `docs/regression-checks.md` | Registration and command line |
| `docs/validation/d3d12-cold-menu-2026-10-28/README.md` | Investigation, evidence, results, known limits |
| `CHANGELOG.md` | Unreleased entry |

No game script changes. **A PCK-only update cannot apply the fix.** The Windows
executable must be rebuilt. Linux, macOS, Android and web templates do not
carry the FSR/DLSS patches this one edits; do not apply it there.

## Integration steps

1. Follow the repository `AGENTS.md` "Local main and remote updates" workflow on
   the canonical checkout. Fetch, merge this branch into local main
   (fast-forward if possible), and keep any accepted local work.
2. Rebuild the Windows release executable from pristine Godot 4.7
   `5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88` plus the 24 Windows patches, in the
   order of the recipe:
   - the 16 common patches;
   - `water-raytracing-uniform-stages`, `experimental-fsr`, `water-raytracing-d3d12`, `d3d12-device-diagnostics`;
   - `restore-dlss`, `dlss-camera-contract`, `dlss-ray-reconstruction`;
   - `temporal-shader-preparation`.

   The test build here used the same SCons flags as the earlier native builds:

   ```text
   platform=windows arch=x86_64 target=template_release production=yes
   optimize=speed debug_symbols=no lto=none use_mingw=yes use_static_cpp=yes
   d3d12=yes agility_sdk_multiarch=yes use_fsr_sdk=yes use_streamline=yes
   use_pix=no accesskit=no winrt=no module_mono_enabled=no
   module_openxr_enabled=no disable_path_overrides=yes
   ```

   with the pinned Streamline 2.14.16 headers, the FSR SDK, the Agility SDK and
   the Mesa NIR libraries. The 23-patch rebuild here behaved like the published
   1.34.0 executable. Embed `assets/branding/icon.ico` and verify it in the final
   EXE, as `AGENTS.md` requires.
3. Run the regression **on native Windows with an NVIDIA RTX GPU**. It needs a
   real D3D12 driver and DLSS runtime; it cannot run under GPU Lab or
   Wine/Proton:

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\run_native_d3d12_cold_start.ps1 `
     -Package <new windows package> -SeedPackage <previous release package> `
     -OriginalGame <owned base game>
   ```

   All three modes (DLSS, TAA, FSR 2) must pass. With 1.34.0 as the package,
   all three fail (38–40 s single frames).
4. Run the related Windows checks on the new executable: `rtx_frame_generation.gd`
   (also via `tools/run_native_dlss_qualification.ps1`), `path_trace_rr_live.gd`
   and `path_trace_rr_guides.gd`. Results from this machine are in the README.
   Run the usual release regressions on the integrated source.
5. When packaging, copy `tools/run_native_d3d12_cold_start.ps1` and its fixture
   into the package's `qualification/` folder, next to the DLSS qualification.
   Release notes: describe the change in neutral terms; there is no GitHub issue.

## Integration status (integration workstation, 2026-10-28)

- Step 1 done: merged into local main; the only conflict was the two Unreleased
  `CHANGELOG.md` entries, both kept.
- Integration review: the TAA/FSR 2 cases only checked that the mode was
  selected and stopped 30 frames after the menu. The patch now also counts
  main-view frames drawn while preparing and with the temporal pass
  (`temporal_preparing_frames`, `temporal_active_frames` in
  `FidelityFX.get_status()`). The fixture requires both for every mode, keeps
  measuring until the mode draws, allows 150 s for that, and no longer holds the
  seed pass to the menu budget.
- Step 2 done as a raw template: the 24-patch Windows template was rebuilt with
  the same command as the 1.34.0 template (the workstation recipe, without the
  `agility_sdk_multiarch`, `winrt` and `disable_path_overrides` flags listed
  above). The 22-patch tree plus `dlss-ray-reconstruction.patch` matched the
  1.34.0 template sources byte for byte before this patch was applied.
  The icon and release metadata come from the release export, which has not run.
- Steps 3–4: under Proton in GPU Lab the published 1.34.0 executable fails every
  mode and the rebuild passes every mode (README, "Proton reproduction").
  The native Windows regression and the native related checks have **not** run
  with the rebuilt executable and are still required.

## Native qualification (Windows test machine, 2026-10-28)

- Steps 3–4 done natively for `main` at `a9f95e07`, as recorded in README
  "Native Windows qualification of the final patch":
  - The final patch rebuilt with the integration flag set gives
    `890c744a3e6e`.
  - The published 1.34.0 executable fails DLSS, TAA and FSR 2 with 30–31 s
    frames.
  - The rebuild passes all three: menu 14–25 s, longest frame 8.0–12.5 s,
    each mode drew after preparation.
  - `rtx_frame_generation.gd` 68/68, `path_trace_rr_live.gd` 38/38 and
    `path_trace_rr_guides.gd` 95/95, natively.
- Remaining for the release:
  - build the release executable through the normal export, with the embedded
    icon and metadata;
  - run the native regression once more on that exact package, because the
    release executable will have a different hash;
  - copy the runner and fixture into `qualification/`;
  - capture PresentMon pacing if the release checklist requires it.
- Step 5 is for the next release build: its recipe must copy the runner and
  fixture into `qualification/`.

## Not done here

- No commit to main, no push of main, no release, no version bump.
- The test executables in `builds/dx12-dlss-deadlock/` (ignored by Git) are
  for local testing only. They are not release artifacts: no embedded icon, no
  release metadata.
- Follow-ups, not part of this fix:
  - the 7–8 s ordinary-shader frame for materials whose generated code changed;
  - the slow (about 1 minute) background start of DLSS on a 4-thread pool;
  - the engine features listed under "Known limits".
