extends Node
## Run with an isolated user profile and --tool=<absolute path to this file>.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _ready() -> void:
	var old_scale := GameData.option("coop_scale")
	var w := GameWorld.new()
	w.time = 1.0
	var u := GameUnit.new()
	u.uid = 10; u.faction = 2; u.world = w
	u.proto = {"name":"activity-health", "senses":PackedFloat32Array([10, 0, 0])}
	u.stats.sight = 10.0
	u.parts = [
		{"type":0,"size":1.0,"lethal":0.5,"cur":10.0,"max":10.0,"state":3},
		{"type":1,"size":1.0,"lethal":0.5,"cur":10.0,"max":10.0,"state":3}]
	u.set_meta("calm", {"busy":true,"until":5.0})
	w.units = {u.uid:u}
	var a := w.ai.activity
	a.enabled = true
	for strength in [1,2,3]:
		GameData.options["coop_scale"] = strength
		for players in [2,3,4]:
			MobScaling.apply(w, players)
			a.begin_tick(GameUnit.TICK)
			check(u._hp < u.max_hp and u.hp == u.max_hp, "scaled body is healthy despite stale fallback %d/%d" % [strength,players])
			check(a.defer_decision(u), "healthy co-op actor keeps calm deadline %d/%d" % [strength,players])
			u.parts[1].cur *= 0.5
			check(u.hp < u.max_hp and not a.defer_decision(u), "real body damage wakes scaled actor")
			u.heal(1000.0)
			check(u.hp == u.max_hp and a.defer_decision(u), "fully healed body returns to deadline scheduling")
			u.parts[1].cur *= 0.5
			MobScaling.apply(w, 1)
			a.begin_tick(GameUnit.TICK)
			check(u._hp == u.max_hp and u.hp < u.max_hp and not a.defer_decision(u), "unscaled fallback cannot conceal a wound")
			u.heal(1000.0)
	GameData.options["coop_scale"] = old_scale
	w.units = {};u.free();w.free()

	print("AI_HEALTH_CHECKS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
