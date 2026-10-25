extends Node
## Cold production campaign attachment must publish and prepare the destination
## atmosphere before returning to play, without requiring a terrain process tick.
const VolumeNoise = preload("res://src/game/fx/cloud_volume_noise.gd")
var checks := 0
var failures := 0
var rows := []
func check(ok: bool, label: String) -> void:
	checks+=1
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	run.call_deferred()

func run() -> void:
	for option:Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.merge({"gfx_clouds":3,"gfx_sky":1,"auto_graphics":0,"display_mode":0,"q_aa":0,"q_shadows":0,
		"render_scale":4,"vsync":0,"fps_limit":30,"confine_mouse":0,"show_fps":1,
		"volume_sfx":0,"volume_stream":0,"volume_voice":0,"show_tutorial":0,"autosave":0,
		"net_lan":0,"net_upnp":0,"net_directory":0,"pt_mode":0,"q_reflections":0,
		"fsr_upscaling":0,"fsr_frame_generation":0,"rtx_upscaling":0,"rtx_frame_generation":0},true)
	GameData._apply_audio();GameData._apply_window();Engine.max_fps=30
	get_tree().root.size=Vector2i(960,540)
	check(VolumeNoise.supported(),"actual render device supports volumetric cloud preparation")
	if failures:finish();return
	var session := Session.new();add_child(session)
	var game := Game.new();game.session=session;session.game=game;add_child(game)
	session.state.ensure_hero(0,"Human Hero")
	Gfx.clear_clouds()
	check(Gfx._cloud_volume_noise==null,"cold atmosphere before campaign load")
	var zone:Dictionary=session.campaign.zone_by_map("zone3obr")
	var started:=Time.get_ticks_usec()
	session._enter_zone(zone.id,1,false)
	var t:=session.world.terrain
	var prepared:=Gfx._cloud_volume_noise
	check(game.world==session.world and t!=null,"production campaign attaches the destination world")
	check(Gfx._cloud_owner==t.get_instance_id() and t._clouds!=null,"destination cloud globals are published during load")
	check(prepared!=null and prepared.shape!=null and prepared.detail!=null,"cold volume noise is ready before the first gameplay tick")
	var before:Dictionary=Gfx._cloud_frame.duplicate(true)
	var wave_time:=t._waves.time_ticks()
	started=Time.get_ticks_usec();t._update_cloud_parameters()
	rows.append({"case":"first explicit terrain cloud update after load","usec":Time.get_ticks_usec()-started,"prepared_during_load":prepared!=null,"setup_ms":Gfx._cloud_volume_noise.setup_ms if Gfx._cloud_volume_noise else -1.0})
	check(prepared!=null and Gfx._cloud_volume_noise==prepared,"first terrain update reuses prepared resources")
	check(t._waves.time_ticks()==wave_time and Gfx._cloud_frame==before,"preparation does not advance the cloud or wave clock")
	# Reattaching a retained world must publish its own frame without allocating
	# another noise volume; old-world teardown cannot clear the new owner.
	game.attach_world(session.world)
	check(Gfx._cloud_volume_noise==prepared,"retained-world attachment reuses noise")
	game.world.zone.sky="cave";game.attach_world(session.world)
	check(Gfx._cloud_frame.state.w==0 and Gfx._cloud_volume_noise==null,"cave attachment clears active volume before rendering")
	game.world.zone.erase("sky");GameData.options.gfx_clouds=1;game.attach_world(session.world)
	check(Gfx._cloud_frame.state.w==1 and Gfx._cloud_volume_noise==null,"sheet-only attachment allocates no volume")
	GameData.options.gfx_clouds=0;game.attach_world(session.world)
	check(Gfx._cloud_owner==0 and Gfx._cloud_volume_noise==null,"disabled-cloud attachment clears ownership")
	game.queue_free();session.queue_free()
	for i in 3:await get_tree().process_frame
	finish()

func finish() -> void:
	FileAccess.open("user://cloud-load-preparation.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("CLOUD_LOAD_PREPARATION checks=",checks," failures=",failures)
	get_tree().quit(int(failures>0))
