# Owned renderer adaptations — 8 October 2026

Worktree: `/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008`  
Branch: `improve/owned-renderer-wounds-textures`  
Starting commit: `3172ede12a5f41b0182c34a70b5eeda787c95e52`

The source audit and priorities are in
[OWNED_RENDERER_IMPROVEMENT_HANDOFF.md](/home/llm2x/Documents/EI/OWNED_RENDERER_IMPROVEMENT_HANDOFF.md).
This checkout is isolated from the ongoing rune, dialogue-camera and co-op work
in “Optimize game performance”. It does not modify that chat's working files,
installed builds or test profiles.

## P1: retain outfit pixels for wounds

Implemented the first P1 step. `EIUnitModel._compose` retains the final,
mip-free CPU source image on its newly created texture. `UnitWounds._wounded`
shares that immutable image with its worker instead of calling
`Texture2D.get_image`. The worker still owns and blends a duplicate, so the
original texture/source remains unchanged. Texture ownership controls source
lifetime; clearing wound caches cannot trigger another readback for the outfit.

Custom textures without a retained source keep the existing once-per-cache
readback. The native wound composition, mip generation, material assignment and
late-job rejection remain unchanged. This removes the normal outfit readback;
it does **not** yet implement the larger wound-only shader-overlay proposal or
remove all wound composition/uploads.

Cost: one additional mip-free RGBA8 source per cached outfit texture
(64 KiB for 128 × 128; 16 KiB for 64 × 64), shared across its wound combinations.

### Validation

- Godot 4.7 stable, isolated application-data directories, headless Linux.
- `tools/tests/wound_source.gd`: **39 checks, zero failures**.
- Checks cover byte-identical results including generated mipmaps, zero source
  readbacks, cached fallback readback, immutable source pixels, cache eviction,
  healing while a job is pending, redressing while an older job is pending,
  and three real shipped redress texture sources.
- Same fixture against the starting production code: **six relevant failures**,
  including readback use and missing producer retention.
- The test's texture spy exercises the real wound entry point and worker; a
  headless run is not presented as a GPU frame-time measurement.
- Evidence: `/home/llm2x/Documents/EI/local/scratchpad/owned-renderer-improvements-20261008-qa/wound-source-control.log`
  and `wound-source-candidate.log`.
- No FPS gain is claimed. Gameplay/GPU timing and mobile validation remain
  separate from this correctness check.

## Integration

The implementation is in this isolated branch. Do not overwrite another agent's
working checkout or installed packages to test it. Integrate the focused commits
once the active source owner can accept them, preserving their newer changes.

