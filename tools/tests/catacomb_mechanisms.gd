extends Node
## Original Catacombs script and floor geometry. No enemy simulation in this
## mechanism test; a normal playthrough and co-op boarding are separate.
var checks := 0
var failures := 0
class CountCombat extends Combat:
	var hits := 0
	func melee(_a: GameUnit, _b: GameUnit, _roll := {}) -> void: hits += 1
	func weapon_spell(_a: GameUnit, _b: GameUnit) -> void: pass

var s: Session
var g: Game
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func ticks(n: int) -> void:
	for i in n:
		s.world.time += GameUnit.TICK
		s.world.vm.tick(GameUnit.TICK)
func offset() -> float:
	return s.world.objects[2240358].get_meta("ei").position.z
func until_stop(height: float, lever: int) -> bool:
	for i in 1800:
		ticks(1)
		if is_equal_approx(offset(),height) and s.world.lever_sys.usable(lever) and int(s.world.levers[338779].state)==0 and int(s.world.levers[1357456].state)==0:
			return true
	print("LIFT_STOP ",offset()," ",s.world.levers[338779]," ",s.world.levers[1357456])
	return false
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_directory":0,"net_lan":0,"camera_style":1},true)
	s = Session.new(); add_child(s)
	g = Game.new(); g.session = s; s.game = g; add_child(g)
	s.set_physics_process(false)
	s.state = CampaignState.new(); s.state.ensure_hero(0,"Human Hero")
	s.state.set_var(0,"q.gz1d2.q03h",1)
	await s.enter_zone("gz1d2",1,false)
	s.world.set_process(false); s.world.set_physics_process(false)
	var hero: GameUnit = s.party_units(0)[0]
	ticks(30)
	check(not s.world.lever_sys._fast(2240358),"Catacombs lift does not use the drawbridge motion policy")
	s.world.vm._use_lever(hero,1369841)
	check(until_stop(28.654,1357456),"original initial call raises the lift")
	for trip in 3:
		s.world.vm._use_lever(hero,1357456)
		check(until_stop(-0.3,338779),"original down trip "+str(trip))
		s.world.vm._use_lever(hero,338779)
		check(until_stop(28.654,1357456),"original up trip "+str(trip))
	s.world.vm._use_lever(hero,1357456)
	check(until_stop(-0.3,338779),"leave lift below for a separated party")
	s.world.vm._use_lever(hero,1369841)
	var recalled := until_stop(28.654,1357456)
	check(recalled,"stationary call lever recalls the lift after its first trip")
	if not recalled:   # isolate later floor checks from the baseline recall failure
		s.world.vm._use_lever(hero,338779)
		check(until_stop(28.654,1357456),"baseline recovery through the moving up lever")
	# The camera's focus should use the same raised floor as actors.
	var lift: Dictionary = s.world.objects[2240358].get_meta("ei")
	print("LIFT_LOCATION ",lift.position," template=",lift.template)
	var p := Vector2(lift.position.x,lift.position.y)
	var floor_z := s.world.ground_at(p.x,p.y)
	print("CAMERA_FLOOR ",p," actor=",floor_z," terrain=",s.world.terrain.height_at(p.x,p.y))
	g.rig.terrain = s.world.terrain; g.rig.position = Vector3(p.x,0,-p.y)
	g.rig._follow_unit = null; g.rig._ground_init = false
	g.rig._update_ground(g,0.016)
	check(g.rig.position.y >= floor_z,"free camera focus remains above the lift floor")
	var high := Vector2.INF
	var low := Vector2.INF
	# Find the raised floor's edge, not the center of the broad navigation
	# footprint: a real adjacent pair must still be inside planar melee reach.
	for dy in range(-16,17):
		if low != Vector2.INF: break
		for dx in range(-16,17):
			var q := p + Vector2(dx,dy)*0.5
			if s.world.ground_at(q.x,q.y) < floor_z-2.0: continue
			for step: Vector2 in [Vector2(0.75,0),Vector2(-0.75,0),Vector2(0,0.75),Vector2(0,-0.75)]:
				var r := q+step
				if s.world.ground_at(r.x,r.y) < floor_z-10.0:
					high = q; low = r; break
			if low != Vector2.INF: break
	check(low != Vector2.INF,"actual lift edge has adjacent positions on separate storeys")
	if low != Vector2.INF:
		var victim := GameUnit.new(); victim.world = s.world; victim.figure_half_z = 0.9; victim.figure_radius = 0.4
		victim.pos = low; victim.controller = -1
		var combat := CountCombat.new(s.world)
		var previous := s.world.combat; s.world.combat = combat
		hero.pos = high; hero.stats.ranged = false
		hero._resolve_hit(victim,{"hit":true})
		check(combat.hits == 0,"committed melee cannot hit a creature far below the actual lift")
		var hit_count := combat.hits
		victim.pos = high
		hero._resolve_hit(victim,{"hit":true})
		check(combat.hits == hit_count+1,"same-floor melee still lands")
		hit_count = combat.hits
		victim.pos = low
		hero._resolve_hit(victim,{"hit":true})
		check(combat.hits == hit_count,"moving to another storey during the swing cancels its hit")
		s.world.combat = previous; combat.world = null; victim.free()
	if DisplayServer.get_name() != "headless":
		g.rig.set_process(false)
		for view in 3:
			g.rig.set_pose({"at":[p.x,floor_z+4.0,-p.y],"yaw":view*TAU/3.0,"distance":24.0,"tilt":0.0,"free":true})
			for frame in 12: await get_tree().process_frame
			var file := "user://catacomb-view-%d.png"%view
			check(get_viewport().get_texture().get_image().save_png(file)==OK,"rendered Catacombs camera view "+str(view))
			print("CAMERA_IMAGE ",ProjectSettings.globalize_path(file))
	g.queue_free(); s.queue_free()
	for i in 8: await get_tree().process_frame
	print("CATACOMB_MECHANISMS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
