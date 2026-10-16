extends "third_person_kbm.gd"
## Actual prone native figure and camera, sampled against loaded map geometry.
func _ready() -> void:
	mode="first-person camera collision"
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"auto_graphics":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"control_mode":3,"direct_fov_first":12,"pad_enabled":0,"confine_mouse":0},true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero");await s.enter_zone("gz15h",1,false);await prepare()
	if OS.get_cmdline_user_args().has("--wide"):
		get_viewport().size=Vector2i(3440,1440);await frames(3)
		check(get_viewport().get_visible_rect().size==Vector2(3440,1440),"ultrawide projection uses actual 3440 by 1440 viewport")
	hero.set_process(false);hero.set_physics_process(false);hero.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	hero.stance=GameUnit.STANCE_CRAWL;hero.model.pose_state=EIUnitModel.ST_LIE;hero.model.act("idle",1,0)
	hero.model.player.advance(0);hero.model.set_process(false)
	var t := s.world.terrain;var sites := 0;var clipped := 0;var unsafe := 0;var flat_unchanged := 0;var corrected := [];var moved:=0;var corners_in_scenery:=0;var corner_examples:=[]
	for y in range(8,int(t.size_ei().y)-8,8):
		for x in range(8,int(t.size_ei().x)-8,8):
			var at := Vector2(x,y)
			if not s.world.nav.cell_open(at,hero.move_class()):continue
			hero.pos=at;hero._sync_transform(0);var body:=hero.global_position
			for direction_index in 8:
				var heading := float(direction_index)*TAU/8
				g.direct.heading=heading;g.direct.tilt=0;g.direct._eye_model=null
				g.direct.apply_camera()
				var local_eye:Vector3=hero.model.transform*hero.model.view_eye_offset(EIUnitModel.ST_LIE)
				var wanted:=body+Basis(Vector3.UP,heading+GameUnit.MODEL_YAW_OFFSET)*local_eye+Vector3(cos(heading),0,-sin(heading))*.28
				var clear:=DirectCombat.scene_clear(s.world,wanted,.10)
				var actual:=g.rig.camera.global_position
				var safe:=DirectCombat.scene_clear(s.world,actual,.09)
				sites+=1;unsafe+=int(not safe)
				if not clear:
					clipped+=1
					if corrected.size()<5:corrected.append({"foot":str(body),"wanted":str(wanted),"camera":str(actual),"safe":safe})
				elif actual.is_equal_approx(wanted):flat_unchanged+=1
				moved+=int(hero.global_position!=body or hero.pos!=at)
				var extent:=g.rig.camera.get_viewport().get_visible_rect().size
				for pixel:Vector2 in [Vector2.ZERO,Vector2(extent.x,0),Vector2(0,extent.y),extent]:
					var corner:=g.rig.camera.project_position(pixel,g.rig.camera.near)
					corners_in_scenery+=int(not DirectCombat.point_clear(s.world,corner))
					if not DirectCombat.point_clear(s.world,corner) and corner_examples.size()<5:
						corner_examples.append({"eye":str(actual),"corner":str(corner),"ground":s.world.ground_at(corner.x,-corner.z),"heading":heading,"extent":str(extent)})
	check(moved==0,"every camera adjustment preserves actor position")
	check(corners_in_scenery==0,"near-plane corners remain outside scenery at maximum first-person FOV")
	check(sites>1000 and clipped>10,"real prone head intersects hills or authored scenery in sampled sites")
	check(unsafe==0,"all drawn eyes retain ground and obstacle clearance")
	check(flat_unchanged>1000,"unobstructed prone camera retains original eye position")
	print("CAMERA_SAMPLES ",JSON.stringify({"sites":sites,"original_clips":clipped,"unsafe":unsafe,"unchanged":flat_unchanged,"examples":corrected,"corners_in_scenery":corners_in_scenery,"corner_examples":corner_examples}))
	g.free();s.free();await frames(6);TexUpscale.shutdown()
	print("FIRST_PERSON_CAMERA ",checks," checks ",failures.size()," failures");get_tree().quit(0 if failures.is_empty() else 1)
