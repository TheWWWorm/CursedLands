extends Node
## Draw actual overhead bars and the portrait with an installed HD Lands atlas.
## Record their source/destination regions at full and partial health.
class RecordedBars extends EnemyBars:
	var regions: Array = []
	func _draw() -> void:
		regions.clear()
		super._draw()
	func _region(dst: Rect2, uv: Rect2, mod: Color, plain: Color) -> void:
		regions.append([dst,uv])
		super._region(dst,uv,mod,plain)

var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)
func frames(n := 5) -> void:
	for i in n: await get_tree().process_frame
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var atlas_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--atlas="): atlas_path = arg.trim_prefix("--atlas=")
	check(not atlas_path.is_empty(), "HD atlas path supplied")
	if atlas_path.is_empty(): get_tree().quit(1); return
	var image := EIMmp.decode(FileAccess.get_file_as_bytes(atlas_path))
	check(image != null and image.get_width() > 256, "decode high-resolution installed atlas")
	if image == null: get_tree().quit(1); return
	image.flip_y()
	var atlas := ImageTexture.create_from_image(image)
	GameData.options.merge(GfxPresets.values(GfxPresets.LOW),true)
	GameData.options.merge({"autosave":0,"auto_graphics":0,"control_mode":0,"enemy_hp_bars":2,"show_tutorial":0,"confine_mouse":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	var s := Session.new(); add_child(s)
	var g := Game.new(); g.session=s; s.game=g; add_child(g)
	s.state.ensure_hero(0,s._hero_proto(0)); await s.enter_zone("gz21k" if GameData.campaign_id == CampaignProfile.ASTRAL else "gz1g",1,false)
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false); s.world.vm.instances.clear()
	g.rig.set_process(false); g.direct.set_process(false); g.hud._dialog.hide()
	var hero := s.party_units(0)[0] as GameUnit
	var foe := s.world.units.values().filter(func(u): return u.controller < 0 and not u.dead and u.model != null)[0] as GameUnit
	foe.pos=hero.pos+Vector2(2,0); foe.hidden=false; foe.visible=true; foe._sync_transform(0); hero._sync_transform(0)
	var cam := g.rig.camera
	cam.global_position=foe.global_position+Vector3(5,3,5); cam.look_at(foe.global_position+Vector3.UP*foe.figure_half_z); cam.reset_physics_interpolation()
	var original := EnemyBars.of(g); original.set_process(false); original.hide()
	var bars := RecordedBars.new(); bars.game=g; original.get_parent().add_child(bars); bars.set_process(false); bars._atlas=atlas
	bars._alpha={foe.uid:1.0}; bars._units={foe.uid:[foe,1.0]}
	g.hud.unit_panel._atlas=atlas; g.hud.unit_panel.examine=foe; g.hud.unit_panel.open=true
	var rows := []
	for fraction: float in [1.0,0.75,0.5,0.25,0.0]:
		foe.hp=foe.max_hp*fraction; bars._health.clear(); bars.queue_redraw(); await frames()
		check(bars.drawn.has(foe.uid), "actual bar drawn " + str(fraction))
		check(bars.regions.size() == (2 if fraction > 0 else 1), "empty bar has only its frame " + str(fraction))
		if bars.regions.size() == 2:
			var dst: Rect2=bars.regions[1][0]; var uv: Rect2=bars.regions[1][1]
			var frame: Rect2=bars.regions[0][0]
			check(is_equal_approx(uv.size.x,100.0*fraction), "full texture range cropped by health " + str(fraction))
			check(is_equal_approx(dst.size.x/frame.size.x,50.0/60.0*fraction), "small bar retains its size " + str(fraction))
			rows.append({"health":fraction,"source_width":uv.size.x,"screen_width":dst.size.x,"frame_width":frame.size.x})
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var shot := get_viewport().get_texture().get_image()
			check(shot.save_png("user://health-gradient-" + str(roundi(fraction*100)) + ".png") == OK,"capture " + str(fraction))
			if fraction == 1.0 and bars.regions.size() == 2:
				var dst: Rect2=bars.regions[1][0]
				# Sample both ends below the white highlight; the old half-strip
				# sampling made the full bar end at yellow instead of green.
				var left := shot.get_pixelv(Vector2i(dst.position+Vector2(dst.size.x*0.08,dst.size.y*0.75)))
				var right := shot.get_pixelv(Vector2i(dst.position+Vector2(dst.size.x*0.92,dst.size.y*0.75)))
				check(left.r > left.g and right.g > right.r,"rendered full bar contains both red and green ends")
	FileAccess.open("user://health-bar-gradient.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"atlas":atlas_path,"samples":rows},"  "))
	print("HEALTH_BAR_GRADIENT ",checks," checks ",failures," failures")
	g.queue_free(); s.queue_free(); await frames(2); get_tree().quit(1 if failures else 0)
