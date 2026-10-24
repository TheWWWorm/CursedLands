class_name MagicTraps
extends RefCounted
## The zone's magic traps (.mob MAGIC_TRAP records), the original
## CMagicTrapObject (vtable 73e63c): set up from the record and run the object
## update (52ac20) on every 55 ms server tick. Host only.
##
## - Active = object flag 0x80000, set by the constructor; script
##   ActivateTrap(trap, 0 / 1) clears / sets it.
## - Interval >= 1: a countdown (+0x288) runs down by one per tick; below 1 an
##   active trap selects its units (52ab30). Interval < 1: an active trap
##   selects them every tick against its seen list (52a680).
## - Selection (52a920) takes every object in the server unit grid within
##   an area's radius, skips the ones whose virtual +0xdc returns non-zero,
##   then tests the player mask. For units that virtual is never 0: in 1.06 a
##   trap selects no unit, so it never casts (52a4b0 returns on an empty list)
##   and its countdown stays at 0. Checked in Wine on the gz3g idol (trap
##   4515, mask -1, 2026-10-24): the leader, an orc and a goblin standing in the
##   area were never hit, also after ActivateTrap(trap, 1). With the +0xdc call
##   patched to return 0 the same trap killed the leader on its next cast.
##   Spell, areas, targets and mask therefore never take effect.

var world: GameWorld
var traps := {}   # nid -> {pos, spell, interval, active, timer}


func _init(w: GameWorld) -> void:
	world = w


## Registers a MAGIC_TRAP record; the defaults are those of the
## record constructor (interval 15).
func add(o: Dictionary) -> void:
	var nid := int(o.get("nid", 0))
	traps[nid] = {"pos": o.get("position", Vector3.ZERO), "spell": String(o.get("trap_spell", "")),
		"interval": int(o.get("trap_interval", 15)), "active": true, "timer": 0}


## Script ActivateTrap (builtin 0x95): flag on / off.
func set_active(nid: int, on: bool) -> void:
	if traps.has(nid):
		traps[nid].active = on


func save_state() -> Dictionary:
	var out := {}
	for nid in traps:
		out[nid] = [traps[nid].active, traps[nid].timer]
	return out


func restore_state(s: Dictionary) -> void:
	for nid in s:
		if traps.has(int(nid)):
			traps[int(nid)].active = bool(s[nid][0])
			traps[int(nid)].timer = int(s[nid][1])


## One 55 ms server tick: only the countdown of a trap with a spell moves,
## as no unit is ever selected.
func tick() -> void:
	for nid in traps:
		var t: Dictionary = traps[nid]
		if String(t.spell).is_empty() or int(t.interval) < 1 or int(t.timer) < 1:
			continue
		if world.active_set.trap_awake(int(nid)):
			t.timer = int(t.timer) - 1
