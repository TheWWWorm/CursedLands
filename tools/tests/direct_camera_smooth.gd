extends "third_person_kbm.gd"
## Camera continuity with a stepped authority yaw and a rotating wall sweep.
class WallWorld extends GameWorld:
	func ground_at(x:float,_y:float)->float:return 8.0 if x>=20.0 else 0.0
func _ready()->void:
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":3,"pad_enabled":0,"blood":0},true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	mode="first person";await s.enter_zone("gz1g",1,false);await prepare()
	hero.set_process(false);hero.set_physics_process(false);hero.direct_controlled=true
	hero.action="idle";g.direct.heading=.4;g.direct.tilt=.1;g.direct.apply_camera(1.0/120)
	var origin:=g.rig.camera.global_position
	var old_origin:=hero.model.to_global(g.direct._eye_offset)
	var old_jump:=0.0;var new_jump:=0.0
	for step in 80:
		hero.facing=step*.17;hero._sync_transform(0);g.direct.apply_camera(1.0/120)
		old_jump=maxf(old_jump,old_origin.distance_to(hero.model.to_global(g.direct._eye_offset)))
		new_jump=maxf(new_jump,origin.distance_to(g.rig.camera.global_position))
	check(old_jump>.01,"authored off-centre eye reproduces movement from stepped body yaw")
	check(new_jump<.00001,"stepped body yaw no longer moves a stationary local camera")
	var worst:=0.0
	for step in 120:
		g.direct.look(Vector2(.035,.001));g.direct.apply_camera(1.0/120)
		var expected:=hero.global_position+Basis(Vector3.UP,g.direct.heading+GameUnit.MODEL_YAW_OFFSET)*(hero.model.transform*g.direct._eye_offset)
		expected+=Vector3(cos(g.direct.heading),0,-sin(g.direct.heading))*.28
		worst=maxf(worst,expected.distance_to(g.rig.camera.global_position))
	check(worst<.00001,"rapid mouse turns use the current frame's continuous eye position")
	var w:=WallWorld.new();add_child(w);w.set_process(false);w.set_physics_process(false)
	var maximum:=0.0;var unsafe:=false
	for step in 160:
		var angle:=-.6+step*.0075
		var a:=Vector3(18,3,0);var ray:=Vector3(cos(angle),0,sin(angle))*4
		var fraction:=DirectCombat.scene_fraction(w,a,a+ray,.18)
		var expected:=(20.0-.18-a.x)/ray.x
		maximum=maxf(maximum,absf(expected-fraction)*ray.length())
		unsafe=unsafe or fraction>expected+.000001
	check(maximum<.002,"rotating shoulder collision has under 2 mm of sweep stepping")
	check(not unsafe,"refined camera sweep stays on the safe side of the wall")
	w.free();g.queue_free();s.queue_free();await frames(8);TexUpscale.shutdown()
	print("DIRECT_CAMERA_SMOOTH ",checks," checks ",failures.size()," failures; old_eye_jump=",old_jump," new_eye_jump=",new_jump," collision_error=",maximum)
	get_tree().quit(0 if failures.is_empty() else 1)
