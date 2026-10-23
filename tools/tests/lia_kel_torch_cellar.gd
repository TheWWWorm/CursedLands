extends "lia_kel_support.gd"
## Real torch use and both Portal-cellar round trips. The supplied checkpoint
## has purchased the first fortune; the ordinary edge reveal runs here.
## This is a passability regression for the reported trap, not a parity
## expectation: the patched original also blocks return while z.gz1h is 1.
const COMPAT := preload("res://src/game/script/story_compat.gd")

func _ready() -> void: run.call_deferred()

func wait_zone(id: String) -> bool:
	var deadline := Time.get_ticks_msec()+45000
	while Time.get_ticks_msec()<deadline:
		if s.world != null and s.zone_id == id and not s.loading_game:
			freeze(); return true
		await get_tree().process_frame
	return false

func leave(number: int, destination: String) -> bool:
	var ex: Dictionary = s.world.zone.exits[number]
	var point: Vector2 = ex.remove.get_center()
	if not check(s.open_exit_at(point,0) == number,
		"usable exit %s:%d to %s"%[s.zone_id,number,destination]): return false
	for u: GameUnit in s.party_heroes():
		u.pos = point; u.resync_drawn()
	var h := hero()
	s.apply_command({"t":"move","units":[h.uid],"x":point.x,"y":point.y,"exit":number},0)
	check(s._leave_armed == number,"deliberate exit click arms selected passage")
	s._check_exits()
	if not check(MessageBox.is_up(game.hud._leave_box),"ordinary exit confirmation opens"): return false
	game.hud._leave_box._answer(true)
	return check(await wait_zone(destination),"confirmed passage loads "+destination)

func negative_guards() -> void:
	check(s._exit_is_open(1) and s._exit_is_open(2),"recognized stock cellar has both return passages")
	for state in [0,1,3]:
		s.state.set_var(0,"z.gz1d1",state)
		check(not s._exit_is_open(1),"cellar state %d is not evidence of the opened torch entrance"%state)
	s.state.set_var(0,"z.gz1d1",2)
	s.state.campaign_id = CampaignProfile.ORIGINAL
	check(not s._exit_is_open(1),"same zone name in original campaign gets no compatibility exemption")
	s.state.campaign_id = CampaignProfile.ASTRAL
	s.lmp = {"fixture":true}
	check(not s._exit_is_open(1),"multiplayer mission mode gets no story exemption")
	s.lmp = {}
	s.zone_id = "gz2h"
	check(not s._exit_is_open(1),"another region keeps its closed destination gate")
	s.zone_id = "gz1d1"
	var exits: Dictionary = s.world.zone.exits
	var original: Dictionary = exits.duplicate(true)
	exits[1].to_exit = 7
	check(not s._exit_is_open(1),"modified return entrance remains authored")
	exits[1] = original[1].duplicate(true)
	exits[2].remove = Rect2(23,82,4,4)
	check(not s._exit_is_open(1),"modified companion return geometry disables the exemption")
	exits[2] = original[2].duplicate(true)
	exits[3] = original[1].duplicate(true)
	check(not s._exit_is_open(3),"an additional modded return is not opened")
	exits.erase(3)
	var portal: Dictionary = s.campaign.zone("gz1h").exits
	var entrance: Dictionary = portal[6].duplicate(true)
	portal[6].to_exit = 2
	check(not s._exit_is_open(1),"modified outer entrance remains authored")
	portal[6] = entrance
	var source := s.world.mob.script_text
	s.world.mob.script_text += "\n"
	check(not s._exit_is_open(1),"modified cellar script remains authored")
	s.world.mob.script_text = source
	var outer := EIMob.load_bytes(GameData.read_file("maps/zone1.mob"))
	check(COMPAT._portal_cellar_sources_match(source,outer.script_text),"both installed scripts match the inspected original contract")
	check(not COMPAT._portal_cellar_sources_match(source,outer.script_text+"\n"),"modified Portal script fails source recognition")
	check(not s._exit_is_open(-1),"missing passage is never opened")
	check(s._exit_is_open(1) and s._exit_is_open(2) and value("z.gz1h") == 1,
		"restoring stock contract restores passage without completing the Portal region")

func retained_world_colours() -> void:
	var owned := s.world
	var fx := ParticleFx.of(owned)
	check(fx.exit_open.is_valid(),"campaign attachment installs its story passage callback")
	s.lmp = {"base":"bz1mpg","quest":"fixture"}
	game.attach_world(owned)
	check(not fx.exit_open.is_valid(),"LMP attachment clears the previous campaign callback")
	# A retained world's effects still process after Session selects another
	# map. Give that map the opposite gate state at the same exit numbers.
	var other := GameWorld.new()
	other.zone = {"id":"fixture","exits":{1:{"to":"gz1d1"},2:{"to":"gz1d1"}}}
	s.world = other
	fx.exit_colours()
	check(s._exit_is_open(1) and fx._exit_fx.all(func(x):return x[0].e.v130.x == 1),
		"retained LMP exits remain red when the selected world's same-number exit is open")
	s.state.set_var(0,"z.gz1h",2)
	s.state.set_var(0,"z.gz1d1",1)
	fx.exit_colours()
	check(not s._exit_is_open(1) and fx._exit_fx.all(func(x):return x[0].e.v130.x == 0),
		"retained LMP exits remain white when the selected world's same-number exit is closed")
	s.world = owned
	other.free()
	s.state.set_var(0,"z.gz1h",1)
	s.state.set_var(0,"z.gz1d1",2)
	s.lmp = {}
	game.attach_world(owned)
	freeze()
	fx.exit_colours()
	check(fx.exit_open.is_valid() and fx._exit_fx.all(func(x):return x[0].e.v130.x == 0),
		"campaign reattachment restores both repaired passage colours")

func visible_passages() -> void:
	var fx := ParticleFx.of(s.world)
	fx.exit_colours()
	check(fx._exit_fx.size() == 2 and fx._exit_fx.all(func(x):return x[0].e.v130.x == 0),
		"both exit effects use their open passage colour")
	for number in [1,2]:
		var point: Vector2 = s.world.zone.exits[number].remove.get_center()
		for u: GameUnit in s.party_heroes(): u.pos = point; u.resync_drawn()
		check(s._party_exit() == number,"party/automatic travel recognizes return "+str(number))
		var pad: PadField = game.get_node("PadField")
		check(pad.labels.entries().any(func(x):return x[3] == "cursor_move" and x[1] == s.zone_title("gz1h")),
			"return %d has its normal world interaction label"%number)
		game.rig.center_on(hero().global_position)
		game.rig.yaw = PI; game.rig.pitch = deg_to_rad(-40); game.rig.distance = 20; game.rig._apply()
		var target := s.world.to_global(EISpace.pos(point.x,point.y,s.world.ground_at(point.x,point.y)))
		var screen := game.rig.camera.unproject_position(target)
		game._exit_hover_p = Vector2.INF
		check(game._over_open_exit(screen),"screen-space ground hover recognizes return "+str(number))
	game.hud.open_quests("field",s.zone_id)
	await frames()
	check(game.hud.quests_screen.entrances.size() == 2 and game.hud.quests_screen.entrances.all(func(e):return e.ok),
		"field objectives show both return arrows as open")
	game.hud.quests_screen.back.emit()
	await frames()
	s.mod_config.rules.auto_exit = 1
	var center: Vector2 = s.world.zone.exits[2].remove.get_center()
	for u: GameUnit in s.party_heroes(): u.pos = center+Vector2(10,0); u.resync_drawn()
	s._check_exits() # entering/loading inside the passage deliberately never auto-leaves
	for u: GameUnit in s.party_heroes(): u.pos = center; u.resync_drawn()
	s._check_exits()
	check(MessageBox.is_up(game.hud._leave_box),"optional automatic exit also opens the return confirmation")
	if MessageBox.is_up(game.hud._leave_box): game.hud._leave_box._answer(false)
	s.mod_config.rules.auto_exit = 0

func run() -> void:
	boot()
	s.mod_config.rules.auto_exit = 0
	s.state.set_var(0,"q.gz1h.q4h",2) # native first-fortune purchase prerequisite
	s.state.set_var(0,"b.skelet.fq2",2)
	s.state.set_var(0,"z.gz1d1",1)
	s._reveal_travel_zones("gz1h_gz2h")
	check(value("z.gz1h") == 1,"ordinary edge traversal reveals Portal at its active region state")
	await enter("gz1h")
	start(["Raja#0","Raja#1","TorchBase#1"])
	var outer: Dictionary = s.world.zone.exits[6]
	check(s.open_exit_at(outer.remove.get_center(),0) == -1,"cellar entrance is closed before torch use")
	use(2261640)
	check(value("z.gz1d1") == 2,"normal torch use opens the authored cellar destination")
	check(value("q.gz1h.fq2") == 0,"opening cellar does not prematurely complete its combat quest")
	if not await leave(6,"gz1d1"):
		await finish("LIA_KEL_TORCH_CELLAR","Prepared purchased first fortune; real travel-region reveal, torch action, explicit exit clicks and confirmations, both cellar exits and save/reload. No original-executable claim."); return
	check(value("z.gz1h") == 1,"cellar entry preserves active Portal quest-region state")
	negative_guards()
	retained_world_colours()
	await visible_passages()
	await roundtrip("lia_torch_inside_cellar",["z.gz1h","z.gz1d1","q.gz1h.fq2"])
	var saved: Dictionary = FileAccess.open(SaveInfo.path("lia_torch_inside_cellar"),FileAccess.READ).get_var()
	check(not JSON.stringify(saved).contains("portal_cellar_sources"),"return recovery needs no new save fields or repair marker")
	for number in [1,2]:
		var ex: Dictionary = s.world.zone.exits[number]
		check(s.open_exit_at(ex.remove.get_center(),0) == number,"cellar exit %d remains usable after save/reload"%number)
	if await leave(1,"gz1h"):
		check(hero().pos.distance_to(outer.deploy.get_center()) < 8,"first return arrives at matching authored entrance")
		if await leave(7,"gz1d1"):
			await roundtrip("lia_torch_second_cellar_entry",["z.gz1h","z.gz1d1"])
			await leave(2,"gz1h")
			check(value("z.gz1h") == 1 and value("q.gz1h.fq2") == 0,
				"both round trips preserve unfinished Portal quest progression")
	# Optional retained pre-fix save: supplied by a recorded replay selection,
	# never from or written over a player's normal profile.
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--save-fixture="): continue
		var old := CampaignState.load_from(arg.trim_prefix("--save-fixture="))
		if not check(old != null and s._load_state("legacy_portal_cellar",old),"retained pre-fix trapped save loads"): continue
		freeze()
		check(s.zone_id == "gz1d1" and value("z.gz1h") == 1 and value("z.gz1d1") == 2,
			"pre-fix save retains the active-region and opened-cellar state")
		check(s._exit_is_open(1) and s._exit_is_open(2),"pre-fix save recovers both returns without a story reset")
		await roundtrip("lia_torch_legacy_recovered",["z.gz1h","z.gz1d1","q.gz1h.fq2"])
		await leave(1,"gz1h")
	await finish("LIA_KEL_TORCH_CELLAR","Prepared purchased first fortune; real travel-region reveal, torch action, explicit clicks and confirmation buttons, both cellar returns, UI, guarded stock-content repair and full saves. Optional retained pre-fix save replay. Intentional repair to a shared original defect; no original-executable parity claim.")
