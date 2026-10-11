extends Node
## Actual authored party: damage protection, mana, healing and revival.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	TutorialPanel.auto_show = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--package="): check(ModStore.import_package(arg.trim_prefix("--package=")) == "", "import actual example")
	check(ModStore.create_profile("Effects sandbox", true) == "", "create isolated sandbox")
	check(ModStore.set_packages(["example.quick-recovery@1.0.0"]) == "" and ModStore.mount() == "", "enable recovery provider")
	var s := Session.new()
	get_parent().add_child(s)
	var g := Game.new()
	g.session = s; s.game = g
	get_parent().add_child(g)
	s.state = CoopProgress.fresh_state()
	await s.enter_zone("bz1g",1,false)
	s.set_physics_process(false)
	s.world.set_process(false); s.world.set_physics_process(false)
	var party := s.party_units(0)
	check(not party.is_empty(), "authored hero is present")
	if party.is_empty(): get_tree().quit(1); return
	var hero: GameUnit = party[0]
	hero._anim_lock = 20.0
	var hp := hero.hp
	hero.take_damage(1.0,null)
	check(hero.hp < hp, "ordinary damage still reduces health")
	check(s.apply_mod_rules({"sandbox_invulnerable":1,"sandbox_mana":1}, {}) == "", "host enables live sandbox rules")
	hp = hero.hp
	hero.take_damage(999999.0,null)
	check(hero.hp == hp and not hero.dead, "invulnerability prevents lethal combat damage")
	hero.mana = 0
	hero.action = "run"
	hero._perceive_next = INF
	hero._anim_lock = 20.0
	hero._tick(GameUnit.TICK)
	check(hero.mana == hero.max_mana, "unlimited mana restores and prevents running drain")
	check(s.sandbox_action("heal") == "" and is_equal_approx(hero.hp,hero.max_hp), "heal restores actual body health")
	hero.dead = true
	hero.hp = 0
	Revive.finish(s, hero)
	check(not hero.dead and is_equal_approx(hero.hp,minf(25.0,hero.max_hp)), "configured revival HP reaches the actual unit")
	check(s.apply_mod_rules({"sandbox_invulnerable":0,"sandbox_mana":0},{}) == "", "sandbox rules can be disabled")
	hp = hero.hp
	hero._anim_lock = 20.0
	hero.take_damage(1.0,null)
	check(hero.hp < hp, "normal damage resumes when protection is disabled")
	g.queue_free(); s.queue_free()
	for i in 5: await get_tree().process_frame
	print("MOD_EFFECTS ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
