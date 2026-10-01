class_name MobScaling
extends RefCounted
## Remake-only co-op option "Scale monsters to player count" (host setting,
## GameData option "coop_scale": 0 Off, 1 Light, 2 Normal, 3 Strong).
##
## the original has no such rule: a network game only forces Normal difficulty
## (see Combat.difficulty) and the LMP maps bring
## their own monsters; nothing in the unit setup
## or the hit code reads the player count.
##
## With n connected players and the strength s (Light 0.25, Normal 0.5,
## Strong 1.0 per extra player), every unit outside the players' parties gets
##   health × (1 + s · (n − 1)),   damage dealt × (1 + s/2 · (n − 1)).
## Experience is not scaled. Applied by the host on the units of the zone (at
## spawn, and every second, so joins, leaves, AddMob units and tamed animals
## follow); health keeps its fraction (GameUnit._set_max_hp), clients get the
## new maximum with the unit snapshots.

const STRENGTH := [0.0, 0.25, 0.5, 1.0]
const CHOICES := ["Off", "Light", "Normal", "Strong"]


static func strength() -> float:
	return float(STRENGTH[clampi(GameData.option("coop_scale"), 0, STRENGTH.size() - 1)])


## Health and damage factors for `players` connected players.
static func factors(players: int) -> Vector2:
	var extra := float(maxi(players, 1) - 1)
	var s := strength()
	return Vector2(1.0 + s * extra, 1.0 + 0.5 * s * extra)


## Host: (re)applies the factors to every unit of `world`. Returns the number
## of units changed.
static func apply(world: GameWorld, players: int) -> int:
	if world == null:
		return 0
	var f := factors(players)
	var n := 0
	for u: GameUnit in world.units.values():
		var target := Vector2.ONE if XpRules.party_of(u) >= 0 or u.has_meta("hero") else f
		if u.dead:
			continue
		var cur := Vector2(float(u.get_meta("coop_hp_mul", 1.0)), float(u.get_meta("coop_dmg_mul", 1.0)))
		if cur.is_equal_approx(target):
			continue
		if is_equal_approx(target.x, 1.0) and is_equal_approx(target.y, 1.0):
			u.remove_meta("coop_hp_mul")
			u.remove_meta("coop_dmg_mul")
		else:
			u.set_meta("coop_hp_mul", target.x)
			u.set_meta("coop_dmg_mul", target.y)
		u.refresh_max_hp()
		n += 1
	return n
