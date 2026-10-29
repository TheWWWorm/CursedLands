extends Node
## A party unit arrives in the next zone with the health and mana it left
## with. The original stores the unit's whole stats block in its party record
## when the party leaves (58fd90 StoreParty → 553360 CopyStats) and a
## redeployed unit gets that block back (5927c0 CreateObject → 477b00
## UnitRecord::ApplyTo): both pools, no spell effects, which live on the unit
## and end with the zone. The remake restored only the health; the mana came
## back full after every zone change (console `travel` and the global map
## share `_enter_zone`), so a drained caster was refilled by walking across a
## zone edge.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func hero(s: Session) -> GameUnit:
	return s.party_units(0)[0]

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	TutorialPanel.auto_show = false
	var s := Session.new(); add_child(s); var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0, s._hero_proto(0))
	await s.enter_zone("gz3g", 1, false)
	var u := hero(s)
	check(is_equal_approx(u.mana, u.max_mana) and is_equal_approx(u.hp, u.max_hp), "a new hero deploys with full pools")
	var max_hp := u.max_hp; var max_mana := u.max_mana
	u.hp = 0.6 * max_hp
	u.mana = 0.3 * max_mana
	u.buffs.eagle_sight = {"until": s.world.time + 600.0, "_effect_ticks": 10800, "sense": [0, 10.0]}
	await s.enter_zone("gz1g", 1, false)
	u = hero(s)
	check(s.zone_id == "gz1g" and u != null, "the party is deployed in the Ruins")
	check(absf(u.hp - 0.6 * max_hp) < 0.5, "health carried into the next zone (%.1f of %.1f)" % [u.hp, max_hp])
	check(absf(u.mana - 0.3 * max_mana) < 0.5, "mana carried into the next zone (%.1f of %.1f)" % [u.mana, max_mana])
	check(u.buffs.is_empty() and u.effect_ticks("eagle_sight") == 0, "spell effects end with the zone left (the record lists none)")
	u.mana = 0.0
	await s.enter_zone("gz3g", 1, false)
	u = hero(s)
	check(s.zone_id == "gz3g" and u.mana < 0.5, "an empty pool stays empty on the way back (%.1f)" % u.mana)
	check(absf(u.hp - 0.6 * max_hp) < 0.5, "health still carried on the way back")
	# The global map advances the clock before the same deployment; the
	# pools are what the record holds, not a function of the hours passed.
	u.mana = 0.5 * max_mana
	s.state.advance_hours(6.0)
	await s.enter_zone("gz1g", 1, false)
	u = hero(s)
	check(absf(u.mana - 0.5 * max_mana) < 0.5, "mana carried after the clock advanced (%.1f)" % u.mana)
	g.queue_free(); s.queue_free(); await get_tree().process_frame
	print("ZONE_CHANGE_POOLS ", checks, " checks ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
