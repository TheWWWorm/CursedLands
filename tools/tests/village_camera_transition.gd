extends "local_host_campaign.gd"
## Real village attachment and shop closure, including first-session defaults.
var observations: Array[Dictionary] = []

func freeze(s: Session) -> void:
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	s.world.vm.instances.clear(); s.world.vm.briefings.active = ""; s.world.vm.briefings._pending_dialog = {}
	s.game.hud._dialog.hide(); s.game.rig.set_process(false)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge(GfxPresets.values(GfxPresets.LOW), true)
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_upnp":0,
		"net_lan":0,"net_directory":0,"control_mode":0,"scroll_border":0,"pad_enabled":0},true)
	TutorialPanel.auto_show = false
	for style in [0,1]:
		GameData.options.camera_style = style; GameData.options.village_start_view = 0; GameData.options.cam_follow = 1
		var s := Session.new(); add_child(s)
		var g := Game.new(); g.session = s; s.game = g; add_child(g)
		s.state.ensure_hero(0,"Human Hero")
		await s.enter_zone("bz1g",1,false); freeze(s)
		var hero: GameUnit = s.party_units(0)[0]
		var authored: Transform3D = preload("res://src/ei/camera_track.gd").read_first(s.world.zone.camera)
		var angle := atan2(authored.basis.z.x, authored.basis.z.z)
		check(is_equal_approx(g.rig.yaw,angle),"first village uses authored angle even with option off, style="+str(style))
		for reset in [0,1]:
			for follow in [0,1]:
				GameData.options.village_start_view = reset; GameData.options.cam_follow = follow
				for action in ["entry","shop"]:
					g.rig.yaw = .73; g.rig.pitch = -.75; g.rig.distance = 22.0; g.rig._apply()
					g.rig.focus(hero.position + Vector3(3,0,3))
					if action == "entry": s._start_pose(s.world.zone,1)
					else:
						g.hud._inventory.open(true,1); g.hud._inventory.hide()
					g.rig._process(0.0)
					var label := "%s style=%d reset=%d follow=%d" % [action,style,reset,follow]
					check(is_equal_approx(g.rig.yaw,angle if reset else .73),label+": expected viewing angle")
					check(Vector2(g.rig.position.x,g.rig.position.z).is_equal_approx(Vector2(g.rig.clamp_look_at(hero.position).x,g.rig.clamp_look_at(hero.position).z)),label+": centred on hero")
					check((g.rig.followed() == hero) == (follow == 1),label+": follow preference respected")
					check(g.rig._opening_view == null,label+": no fixed camera override remains")
					observations.append({"case":label,"yaw":g.rig.yaw,"followed":g.rig.followed()!=null})
		var pose := g.rig.pose()
		g.rig.focus(hero.position+Vector3(3,0,3))
		check(g.rig.set_pose(pose) and is_equal_approx(g.rig.yaw,float(pose.yaw)),"saved orbit restores, style="+str(style))
		g.queue_free(); s.queue_free()
		for i in 5: await get_tree().process_frame
	FileAccess.open("user://village-camera-transition.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"))
	print("VILLAGE_CAMERA_TRANSITION ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
