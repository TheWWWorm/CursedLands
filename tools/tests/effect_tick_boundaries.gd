extends Node
## Authored counter endpoints, host/client lifetime differences, save width and
## independent overlapping effects. Assertions are regression contracts, not
## evidence of a fresh execution of the original game.
var checks := 0
var failures := 0
const COUNTERS := [
	# input, authority after one tick (null = removed), client after one tick
	[-2147483648,2147483647,-2147483648],
	[-1,null,-1], [0,null,0], [1,null,0], [2,1,1],
	[65535,65534,65534], [65536,65535,65535], [65537,65536,65536],
	[2147483647,2147483646,2147483646],
]

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func actor(w: GameWorld) -> GameUnit:
	var u := GameUnit.new()
	u.world=w;u.uid=1;u.max_hp=100.0;u.max_mana=100.0
	return u

func _ready() -> void:
	var w := GameWorld.new()
	var client_world := GameWorld.new();client_world.authority=false
	for time: float in [0.0,100.125,1000000.0]:
		w.time=time;client_world.time=time
		for row: Array in COUNTERS:
			for dead: bool in [false,true]:
				var u:=actor(w);var view:=actor(client_world)
				u.dead=dead;view.dead=dead
				u.buffs={"feeblemind":{"_effect_ticks":row[0],"until":time+999.0,"no_cast":true}}
				view.buffs=u.buffs.duplicate(true)
				var label:="%d at %s dead=%s"%[row[0],time,dead]
				u._tick_effects();view._tick_effects()
				check(view.effect_ticks("feeblemind")==row[0],label+" client cannot run authoritative expiration")
				if row[1]==null:
					check(not u.buffs.has("feeblemind") and not u.cannot_cast(),label+" host removes expired gameplay effect")
				else:
					check(u.effect_ticks("feeblemind")==row[1] and u.cannot_cast(),label+" host preserves exact signed counter")
				view.client_tick_effects()
				check(view.effect_ticks("feeblemind")==row[2] and view.cannot_cast(),label+" client ages presentation without clearing authority's effect")
				u.free();view.free()
	# Saves retain signed 32-bit counters even when they exceed packet width.
	for count: int in [0,1,2,65535,65536,65537,2147483647]:
		w.time=123.25
		var u:=actor(w)
		u.buffs={"speed":{"_effect_ticks":count,"until":-10.0,"actions_add":7.0}}
		var saved: Dictionary=bytes_to_var(var_to_bytes(CampaignState.body_state(u)))
		w.time=9000.0
		var restored:=actor(w);CampaignState.apply_body(restored,saved)
		check(restored.effect_ticks("speed")==count,"saved counter %d survives changed world clock"%count)
		check(restored.actions()==u.actions(),"saved counter %d preserves its modifier"%count)
		var wire: Array=u._buff_snapshot()
		check(int(wire[0][4][GameUnit.EFFECT_TICKS])==(count%65536),"counter %d retains declared 16-bit snapshot format"%count)
		u.free();restored.free()
	var u:=actor(w);u.stats={"actions":15.0}
	u.buffs={
		"feeblemind":{"_effect_ticks":1,"no_cast":true},
		"speed":{"_effect_ticks":2,"actions_add":5.0},
		"strength":{"_effect_ticks":3,"hp_mul":1.5},
	}
	u.refresh_max_hp()
	check(u.cannot_cast() and u.actions()==20.0 and u.max_hp==150.0,"overlapping effects each apply")
	u._tick_effects()
	check(not u.cannot_cast() and u.actions()==20.0 and u.max_hp==150.0,"first expiry clears casting block only")
	u._tick_effects()
	check(u.actions()==15.0 and u.max_hp==150.0,"second expiry clears speed only")
	u._tick_effects()
	check(u.buffs.is_empty() and u.max_hp==100.0,"last expiry restores base maximum HP")
	# Refreshing an active status replaces its remaining duration; the original
	# deadline cannot expire the newly received value.
	u.buffs={"silence":{"_effect_ticks":1,"detect":[1.0,0.0],"until":w.time}}
	u.buffs.silence={"_effect_ticks":3,"detect":[1.0,0.0],"until":w.time}
	u._tick_effects()
	check(u.effect_ticks("silence")==2,"refreshed status outlives the old deadline")
	for value in [null,true,1.0,"1",-2147483649,2147483648]:
		check(not GameUnit.valid_effect_ticks(value),"malformed counter is not accepted: "+str(value))
	for value: int in [-2147483648,0,2147483647]:
		check(GameUnit.valid_effect_ticks(value),"signed endpoint accepted: "+str(value))
	for count in [0,1,2,15,65536]:
		check(GameUnit.legacy_effect_ticks(float(count)*GameUnit.TICK)==count,"legacy exact tick duration migrates: "+str(count))
	check(GameUnit.legacy_effect_ticks(0.125)==-1,"fractional legacy deadline is not rounded to a fabricated tick")
	u.free();w.free();client_world.free()
	print("EFFECT_TICK_BOUNDARIES ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
