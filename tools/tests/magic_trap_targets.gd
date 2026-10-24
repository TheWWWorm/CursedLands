extends Node
## #106/#110: the shrine must hit the party, spare the local creatures,
## retain its cooldown, and still obey the lever after a full save/load.
var checks := 0
var failures := 0
var s: Session
var g: Game

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func freeze() -> void:
	s.set_physics_process(false)
	s.world.set_process(false); s.world.set_physics_process(false)
	g.rig.set_process(false)
	for u: GameUnit in s.world.unit_rows():
		u.set_process(false); u.set_physics_process(false)

func put(u: GameUnit, p: Vector2) -> void:
	u.pos = p; u._sync_transform(0); s.world.nav.track_unit(u)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,
		"net_lan":0,"net_upnp":0,"net_directory":0}, true)
	s = Session.new(); add_child(s); s.set_physics_process(false)
	s.state.ensure_hero(0,"Human Hero")
	g = Game.new(); g.session=s; s.game=g; add_child(g)
	await s.enter_zone("gz3g",1,false); freeze()
	var w := s.world
	var t: Dictionary = w.traps.traps[4515]
	check(int(t.mask)==1, "gz3g owner 2's map diplomacy selects faction 0")
	var raw: Dictionary = w.objects[4515].get_meta("ei")
	check(int(raw.trap_players)==-1, "the raw all-player mask is superseded by map diplomacy")
	var hero: GameUnit = s.party_units(0)[0]
	var gob: GameUnit = w.units[4573]
	var orc: GameUnit = w.units[4497]
	var companion := w.spawn_unit({"prototype":"Human Hero","position":Vector3(202,85,0),"player":0})
	companion.controller=0; companion.mode="player"
	put(hero,Vector2(200,85)); put(gob,Vector2(200,84)); put(orc,Vector2(202,84))
	w.active_set.wake()
	check(w.active_set.trap_awake(4515), "the party wakes the shrine")
	var targets: Array = w.traps._units_in(t)
	check(hero in targets and companion in targets, "Zak and a companion are both selected")
	check(not gob in targets and not orc in targets, "goblin and orc in the same circle are excluded")
	var gob_hp := gob.hp; var orc_hp := orc.hp
	hero.hp=100000.0; companion.hp=100000.0
	var hero_hp := hero.hp; var companion_hp := companion.hp
	w.traps.set_active(4515,false)
	for i in 110: w.traps.tick()
	check(hero.hp==hero_hp and companion.hp==companion_hp, "disabled shrine cannot damage the party")
	# Native mask is captured at map load: runtime peace is not a trap switch.
	w.set_relation(2,0,0)
	check(w.traps._units_in(t).has(hero), "runtime diplomacy does not rewrite the captured mask")
	w.traps.set_active(4515,true)
	w.traps.tick()
	check(hero.hp<hero_hp and companion.hp<companion_hp, "active shrine actually damages both party targets")
	check(gob.hp==gob_hp and orc.hp==orc_hp, "actual lightning leaves both creatures unharmed")
	check(t.timer==100, "a successful cast starts the authored 100-tick countdown")
	w.traps.tick()
	check(t.timer==99, "the next tick counts down without another immediate cast")
	# Save a living party and the disabled trap, using the real Session path.
	w.traps.set_active(4515,false)
	check(s.save_game("trap-disabled")==OK and s.load_game("trap-disabled"), "full trap checkpoint reloads")
	freeze(); w=s.world; t=w.traps.traps[4515]
	check(not t.active and t.timer==99 and t.mask==1, "save/load preserves disabled state, cooldown and captured mask")
	w.traps.restore_state({4515:[true,17]})
	check(t.active and t.timer==17 and t.mask==1, "older two-field trap saves keep the authored target mask")
	# A generic owner can target NPC factions too; this is not a shrine or
	# player-only exception. The same diplomacy row drives every map trap.
	w.set_relation(7,3,2); w.set_relation(7,4,0)
	w.traps.add({"nid":900001,"player":7,"trap_players":0,"trap_spell":"lightning{}"})
	check((int(w.traps.traps[900001].mask)&(1<<3))!=0 and (int(w.traps.traps[900001].mask)&(1<<4))==0,
		"generic trap mask follows owner-to-target hostility")
	var extra_diplomacy := PackedInt32Array(); extra_diplomacy.resize(1024); extra_diplomacy.fill(1)
	extra_diplomacy[7*32+4]=2
	w.traps.add({"nid":900002,"player":7},extra_diplomacy)
	check(w.traps.traps[900002].mask==(1<<4), "AddMob trap uses its source map's diplomacy row")
	hero=s.party_units(0)[0]; put(hero,Vector2(200,85)); hero_hp=hero.hp
	w.objects.erase(4515); t.active=true; t.timer=0
	w.traps.tick()
	check(hero.hp==hero_hp, "a removed trap cannot continue casting")
	g.queue_free(); s.queue_free()
	for i in 6: await get_tree().process_frame
	TexUpscale.shutdown()
	print("MAGIC_TRAP_TARGETS ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
