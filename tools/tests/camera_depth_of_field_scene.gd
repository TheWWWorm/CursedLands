extends "story_coop_traps_net.gd"
## Actual camera-rig lifecycle on the authored Dead City conversation.
const DRAGON:=1000002518

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"auto_graphics":0,"scroll_border":0,"gfx_depth_of_field":1,"gfx_wind":0,"camera_style":0},true)
	host=branch(true);host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero")
	host.set_physics_process(false)
	await host.enter_zone("bz3g",1,false);freeze(host)
	var rig:=host.game.rig
	var dragon: GameUnit=host.world.units[DRAGON]
	var hero: GameUnit=host.party_units(0)[0]
	if not CameraDepthOfField.supported():
		check(rig._depth_of_field==null,"actual unsupported runtime rig has no DOF helper")
		await finish();return
	rig._depth_of_field.set_process(false)
	rig.pitch=-deg_to_rad(25);rig.distance=20;rig.focus(dragon.global_position)
	rig._depth_of_field._process(0.1)
	check(rig.camera.attributes!=null and rig.camera.attributes.dof_blur_far_enabled,"actual low orbit enables optional far blur")
	check(rig._depth_of_field._focus>19.9 and rig._depth_of_field._focus<20.1,"orbit focus follows its current pivot")
	host.world.vm.briefings.play_named("Dr20","b.bz3g.Dr20",0,null,true)
	var panel:=host.game.hud._dialog
	check(await until(func():return panel.visible),"original dialogue opens normally")
	panel.set_process(false);panel._i=2;panel._show()
	var hero_before:=hero.snapshot().duplicate(true)
	rig._depth_of_field._process(0.1)
	check(rig.held and rig.presentation_focus()==rig._held_target,"original dialogue provides actual camera target")
	var wanted:=clampf((rig._held_target-rig.camera.global_position).dot(-rig.camera.global_basis.z),2,600)
	for i in 30:rig._depth_of_field._process(0.1)
	check(rig.camera.attributes!=null and absf(rig._depth_of_field._focus-wanted)<0.01,"dialogue focus settles on authored target")
	check(hero.snapshot()==hero_before,"lens changes no actor gameplay state")
	if DisplayServer.get_name()!="headless":
		# Authored animation continues: this is qualitative camera evidence.
		# Exact foreground/UI/horizon acceptance lives in the synthetic fixture.
		await frames(8)
		check(host.get_viewport().get_texture().get_image().save_png("user://dof-dialogue.png")==OK,"capture original dialogue with optional lens")
	GameData.options.gfx_depth_of_field=0;rig._depth_of_field._process(0.1)
	if DisplayServer.get_name()!="headless":
		await frames(8)
		check(host.get_viewport().get_texture().get_image().save_png("user://dof-dialogue-off.png")==OK,"capture original dialogue after disabling lens")
	check(rig.camera.attributes==null,"live option off releases dialogue camera attributes")
	host.broadcast({"t":"dialog_close","id":"b.bz3g.Dr20"});GameData.options.gfx_depth_of_field=1
	rig.pitch=-deg_to_rad(65);rig._apply();rig._depth_of_field._process(0.1)
	check(not rig.held and rig.camera.attributes==null,"dialogue exit to tactical camera stays sharp")
	GameData.options.control_mode=2
	host.game.selected.assign([hero]);host.game.direct.apply_camera()
	check(rig.presentation_focus().distance_to(hero.global_position+Vector3.UP*clampf(hero.figure_half_z*1.6,0.6,2.8))<0.001,"third-person focus follows the drawn hero pivot")
	print("CAMERA_DOF_SCENE %d checks %d failures"%[checks,failures])
	await finish()
