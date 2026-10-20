extends "local_host_campaign.gd"
## Actual village attachment and retained orbit versus the opt-in authored view.
var observations: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,
		"net_upnp":0,"net_lan":0,"net_directory":0,"control_mode":0,
		"camera_style":0,"scroll_border":0,"pad_enabled":0,"village_start_view":0},true)
	TutorialPanel.auto_show = false
	var s := Session.new(); add_child(s)
	var g := Game.new(); g.session=s; s.game=g; add_child(g)
	s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("gz1g",1,false)
	s.set_physics_process(false); s.world.set_process(false)
	s.world.set_physics_process(false); g.rig.set_process(false)
	s.world.vm.instances.clear()
	g.rig.yaw = .73; g.rig.pitch = -.75; g.rig.distance = 22.0
	g.rig._apply()
	var wanted := Vector3(g.rig.yaw,g.rig.pitch,g.rig.distance)
	await s.enter_zone("bz1g",1,false)
	s.world.set_process(false); s.world.set_physics_process(false)
	s.world.vm.instances.clear()
	var actual := Vector3(g.rig.yaw,g.rig.pitch,g.rig.distance)
	check(actual.is_equal_approx(wanted) and g.rig._opening_view == null,
		"default village entry preserves the player's orbit")
	check(g.rig.followed()==s.party_units(0)[0],"default village view follows the entering hero")
	observations.append({"mode":"default","yaw":actual.x,"pitch":actual.y,"distance":actual.z})
	var authored: Variant = preload("res://src/ei/camera_track.gd").read_first(s.world.zone.camera)
	check(authored is Transform3D,"original village camera asset is available")
	GameData.options.village_start_view=1
	check(g.rig.village_start_view(s.world.zone),"opt-in authored village view applies")
	check(authored is Transform3D and g.rig.camera.global_transform.is_equal_approx(authored),
		"authored view uses the original camera file exactly")
	var saved := g.rig.pose()
	g.rig.focus(s.party_units(0)[0].position)
	check(g.rig._opening_view == null,"recentring leaves the authored view")
	check(g.rig.set_pose(saved) and g.rig.camera.global_transform.is_equal_approx(authored),
		"saved authored view restores without interpreting it as an orbit")
	g.queue_free(); s.queue_free()
	for i in 6:await get_tree().process_frame
	FileAccess.open("user://village-camera-transition.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"))
	print("VILLAGE_CAMERA_TRANSITION ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
