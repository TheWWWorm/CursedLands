# Cursed Lands 1.0.3 Experimental 6

This release brings together the gameplay and handheld improvements developed
since Experimental 5. It requires your own Evil Islands or Lost in Astral data.
All co-op players must update together: the network protocol is now 11.

## Changes

- Ordinary single-player can use a separate simulation process. Includes the
  previously measured Retroid improvements to picking, presentation, particle
  work and worker cadence.
- Co-op transitions show loading earlier and reject old-map commands. Movement
  interpolation, sale transactions, guest names, personal progress and temporary
  Nalo/Shaina/captivity/disguise roles are improved.
- Partial creatures and corpses remain visible in the reproduced geometry
  edge cases. Cross-floor melee, lift recall, camp boundaries/actions, long path
  previews, obstructed dialogue views, Shelter exits and Terror persistence
  receive fixes.
- Full training refunds include initial skills and abilities. Escalating
  ability prices no longer reward a particular purchase order. Gipath's spell
  shop stocks the native weapon/armour infusion runes.
- Spell, template and rune pictures fill their slots. Finished spells use their
  own colours; sale stacks merge and inventory changes apply atomically.
- Experimental third-person controls add a shoulder camera, WASD/stick
  movement, aimed attacks and persistent health bars. Gamepads default to this
  mode; classic controls remain selectable.
- Inspected campaign spells, traps, guard checks and dragon follow cycles
  include extra players while retaining original story roles. Scripted NPC
  behavior survives saves; whole-number script IDs compare exactly.

## Validation and known limits

This is an experimental release with focused regression and packaging checks,
not a completed campaign or platform certification. The detailed coverage is
in [the gameplay tracker](gameplay-gaps-2026-10-08.md).

Performance investigation is deferred at the user's request. Earlier Retroid
Original/1× large-area routes measured about 49–60 FPS; stable 60 FPS everywhere
is not established. The Windows 4K/max/2× report around 40 FPS remains unresolved.
No new performance improvement is claimed from this release's smoke checks.

Remaining investigations include the intermittent Catacombs client slowdown,
internet co-op lag, some slow initial loading, full Terror/temporary-character
quest routes, elevator boarding, and additional camera/third-person coverage.
The last prison-guard check covers already-armed party scripts; a general audit
of late arrivals into all original per-character story checks remains open.

Windows and macOS packages are cross-exported without target-OS runtime
validation. macOS uses the stock engine and script fallbacks, is unsigned and
is not notarized. Android supports ARM64 and retains the public signing key
with version code 16.

## Downloads

Use the archive for your platform, or install the Android APK. No original game
assets or player saves are included. SHA256SUMS.txt accompanies the release.

https://github.com/TheWWWorm/CursedLands/releases/tag/v1.0.3-experimental.6
