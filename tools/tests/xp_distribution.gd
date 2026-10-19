extends Node
## Distribution is checked through the public reward path, with inline/worker
## mode flags, co-op party fixtures, death debt, and persisted rule choices.
var failures := 0
var checks := 0
class ProbeSession extends Session:
	func broadcast(_event: Dictionary) -> void: pass
	func sync_state() -> void: pass
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)
func add_hero(s: Session, id: int, owner: int, merc := false) -> GameUnit:
	var u := GameUnit.new(); u.world=s.world; u.controller=owner; u.uid=id
	var record := {"exp":0.0,"exp_total":0.0,"exp_debt":0.0,"str":25.0,"dex":25.0,"int":25.0,"perks":[]}
	if merc: record.merc=id
	u.set_meta("hero",record); s.world.set_unit(id,u)
	if not merc: s.state.heroes[owner]=[record]
	return u
func _ready() -> void:
	for transport in ["inline","worker","coop"]:
		var s := ProbeSession.new(); s.state=CampaignState.new(); s.world=GameWorld.new(); s.world.session=s
		s.online=transport!="inline"; s.local_host=LocalHost.new(); s.local_host.session=s
		s.local_host.single_player=transport=="worker"
		var main := add_hero(s,1,0); var merc := add_hero(s,2,0,true)
		var second: GameUnit; var other_merc: GameUnit
		if transport=="coop":
			s.players[2]={"index":1,"name":"Second","colour":2}
			second=add_hero(s,3,1); other_merc=add_hero(s,4,1,true)
		for choice in 3:
			GameData.options.sp_full_xp=choice; GameData.options.coop_full_xp=choice
			for source in ["kill","quest","talk","side"]:
				for u: GameUnit in s.world.unit_rows():
					u.get_meta("hero").merge({"exp":0.0,"exp_total":0.0,"exp_debt":0.0},true)
				# Original co-op kill/quest excludes parties with hired heroes;
				# this fixture keeps companions outside heroes[], like live saves.
				if transport=="coop" and choice==0 and source in ["kill","quest"]:
					main.get_meta("hero").exp_total=100.0; second.get_meta("hero").exp_total=100.0
				var before := float(main.get_meta("hero").exp_total)
				XpRules.give(s,100.0,source,0)
				var main_expected := 50.0 if choice==0 else 100.0
				var merc_expected := 100.0 if choice==1 else 50.0
				if transport=="coop" and choice==0 and source in ["kill","quest"]: merc_expected=0.0
				check(is_equal_approx(main.get_meta("hero").exp_total-before,main_expected),"%s mode%d %s main"%[transport,choice,source])
				check(is_equal_approx(merc.get_meta("hero").exp_total,merc_expected),"%s mode%d %s companion"%[transport,choice,source])
				if transport=="coop" and choice==2:
					check(second.get_meta("hero").exp_total==100.0 and other_merc.get_meta("hero").exp_total==50.0,"each co-op main receives full XP; each companion its party share")
			if choice==2:
				main.get_meta("hero").merge({"exp":0.0,"exp_total":0.0,"exp_debt":40.0},true)
				XpRules.give(s,100.0,"side",0)
				check(main.get_meta("hero").exp_debt==0.0 and main.get_meta("hero").exp_total==60.0,"full main still pays death debt")
		for u: GameUnit in s.world.unit_rows(): u.free()
		s.world.units={}; s.world.free(); s.local_host.free(); s.free()
	var config := ModStore.snapshot()
	config.rules.sp_full_xp=2; config.rules.coop_full_xp=2
	check(ModStore.configuration_error(config).is_empty(),"rule schema accepts both third choices")
	var state := CampaignState.new(); state.mod_config=config
	check(state.save("user://xp-choices.sav")==OK,"save accepts XP choices")
	var restored := CampaignState.load_from("user://xp-choices.sav")
	check(restored!=null and restored.mod_config.rules.sp_full_xp==2 and restored.mod_config.rules.coop_full_xp==2,"load retains both choices")
	for locale in ["ru","de"]:
		RemakeText.lang=locale
		for key: String in XpRules.CHOICES+Array(GameData.REMAKE_OPTIONS.sp_full_xp)+Array(GameData.REMAKE_OPTIONS.coop_full_xp):
			check(RemakeText.t(key)!=key,locale+" translated: "+key)
	print("XP_DISTRIBUTION ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
