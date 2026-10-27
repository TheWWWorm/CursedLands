# Foliage, village weapons and ground cover — 27 October 2026

Follow-up to [the initial investigation](foothills-and-graphics-2026-10-27.md).
Local main `f455e844` was merged into the task branch as `17418ea3` before these
changes. No remote update, publication or version change was made.

## White trees and foliage shadows

The supplied `CursedLands-report-20261027-174753.txt` identifies Windows D3D12,
an RTX 5090, and repeated **33 varying declarations / maximum 32** compilation
errors. Its all-effects menu was reproduced with the released Windows 1.32.0
EXE/PCK under registered Proton/VKD3D in GPU Lab. The captured failure has the
same white, opaque trees and shader errors at lines 1282/1285 as the report.

Ground contact already packs the foliage rest position with its contact band.
However, terrain-transition helpers can appear before the packing flag. RT's
common declarations are inserted ahead of the first helper and consequently
compile their unpacked branch too. The extra declaration exceeds the limit;
the fallback loses both texture colour and leaf cutouts.

The packing flag and shared declaration now precede all helper functions.
Wind, terrain transitions, ground contact, fog and PT remain enabled. The
actual menu passes on D3D12 and Vulkan, with green textured foliage and visible
cutouts in the retained captures. This addresses shadows caused by these opaque
fallback tree cards; it is not a claim that every separately reported shadow
artifact has the same cause. This shader combination is remake-only, so an
original-game rendering comparison cannot exercise the failure.

The initial isolated shader test passed because it omitted terrain-transition
helpers. Its final version includes those helpers and fails on the previous
pack. Windows coverage uses the standard released engine and DLLs under
Proton/VKD3D, not native Windows or the reporter's RTX 5090.

## Village weapon visibility

Further native analysis found the missing rule in base-game `005341a0`: each
model update reads the current ADB animation record and calls `00537cb0` with
`(record.code & 0x7fff) == 0`. The latter hides the equipped weapon's parts,
enumerated by `006a0fb0`. Village dialogue selection in `00607a20` uses the
unarmed special animations. Equipped inventory alone does not determine what
the original draws in a safe zone.

The remake now applies that rule when selecting a clip. Speaking/listening
poses hide the weapon, bow/crossbow attachments and ammunition meshes; armed
poses restore them. Inventory previews, authored armed guards, natural creature
parts and the existing protagonist-specific safe-zone appearance stay intact.

Original executable SHA-256:
`d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8`.
The patched LiA 1.02 village checkpoint was also loaded under Wine 11.20 in a
locked, disposable prefix. That probe did not identify the precise foreground
NPC from the screenshot or capture its exact dialogue. The native code rule
and real-asset regression establish this correction; the exact NPC identity
remains unconfirmed. Earlier inspection of helmet handling alone was insufficient.

## Requested ground-cover changes

Production cover no longer enables the extra procedural sand/snow mound
overlay. The admission probability for common scattered stones is halved
(0.12 → 0.06 on rocky ground; 0.025 → 0.0125 elsewhere). Original map objects,
rock placements, terrain heights/normals and footprint deformation are retained.
Base snow pockets and LiA's photographed desert hub are checked. Existing
regional tests still enumerate all authored snow pockets independently of the
removed overlay. These are explicit changes to remake additions; native parity
does not define their density.

## Verification and remaining uncertainty

Evidence root outside the repository:
`local/validation/foothills-118-119-20261026/followup-20261027/`.
Per-run manifests retain source, engine, pack and script hashes.

| Check | Negative control | Candidate |
| --- | --- | --- |
| Actual all-effects menu, D3D12 | 3 failed checks; exact white-tree/error reproduction | 10 checks, zero errors |
| Foliage/transition option matrix | Compiler rejects combined variants | 67 checks each on Vulkan and D3D12 |
| Weapon visibility, base and LiA | 22 failures per campaign | 121 checks per campaign |
| Equipment continuity, creature animations, safe-zone appearance | Existing regressions | 56 + 196 + 11 checks |
| Ground cover, base and LiA | 38 failures per campaign | 46 + 41 checks |
| Existing cover/worker and regional geometry tests | Existing regressions | 7,590 + 14,691 checks |
| PT material receivers | Existing regression | 7 checks |
| Fresh Foothills campaign flow | Diagnostic, not a claimed fix | 18 checks |

**#119 remains unconfirmed.** The additional rendered test uses production
new-campaign startup, Ruins-to-Foothills travel, a real save, return to the menu,
and loading through a fresh authority process. It does not generate an artificial
campaign seed or insert a stale clock cache. Foothills measured approximately
0.98–0.99 simulation seconds per wall second at normal speed and 2.12–2.14 at
fast speed across the two final comparisons. Existing mana/effect-clock tests
are retained. No speculative clock behavior change is included.

The previously reported NVIDIA FG SDK integration failure is also outside this
foliage fix. Working texture/shader output does not establish FG availability.

The selected final runs total 23,052 passing assertions, including both APIs;
this is not a full-repository-suite claim. Failed negative controls and earlier
fixture/setup errors are retained separately from those final results.
