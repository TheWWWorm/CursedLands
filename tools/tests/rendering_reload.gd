extends Node
## Requires descriptor-gz1h/gz2h/bz2h saves in an isolated Lost in Astral profile.
## Render on GPU Lab; exercises the normal separate-authority loading path.
var s:Session
var g:Game
var rows:Array=[]
var failures:Array=[]
var deadline:=0
func _ready():
	process_mode=Node.PROCESS_MODE_ALWAYS
	deadline=Time.get_ticks_msec()+780000
	_run.call_deferred()
func _process(_dt):
	if Time.get_ticks_msec()>deadline:
		failures.append("wall timeout")
		_persist();get_tree().quit(1)
func _persist():
	FileAccess.open("user://descriptor-reload.json",FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"failures":failures,"capacity":ProjectSettings.get_setting("rendering/rendering_device/d3d12/max_resource_descriptors"),"instance_buffer_entries":ProjectSettings.get_setting("rendering/limits/global_shader_variables/buffer_size"),"gpu":RenderingServer.get_video_adapter_name()},"\t"))
func _run():
	if GameData.campaign_id!=CampaignProfile.ASTRAL or DisplayServer.get_name()=="headless":
		failures.append("requires rendered Lost in Astral");_persist();get_tree().quit(2);return
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0,"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_voice":0,"volume_stream":0,"display_mode":0,"resolution":1,"fps_limit":1,"pt_mode":0,"rtx_upscaling":0,"rtx_frame_generation":0,"fsr_upscaling":0,"fsr_frame_generation":0,"q_aa":0},true)
	GameData._apply_window();Gfx.apply_quality(get_viewport());Engine.max_fps=30
	for i in 6:await get_tree().process_frame
	get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1600,900);get_window().position=Vector2i(80,80)
	get_window().grab_focus()
	TutorialPanel.auto_show=false
	s=Session.new();get_parent().add_child(s)
	g=Game.new();g.session=s;s.game=g;get_parent().add_child(g)
	for cycle in 12:
		var zone:String=["gz1h","gz1h","gz2h","bz2h"][cycle%4]
		var previous:=weakref(s.world) if s.world else null
		if not await s.load_game_shown("descriptor-"+zone):
			failures.append("load "+str(cycle));break
		while s.world==null or s._remote_loading or s.loading_game:await get_tree().process_frame
		while ShaderCompilationScreen.active():await get_tree().process_frame
		for i in 60:await RenderingServer.frame_post_draw
		if previous and previous.get_ref()!=null:failures.append("old world retained "+str(cycle))
		var shot:=get_viewport().get_texture().get_image()
		shot.save_png("user://descriptor-%02d-%s.png"%[cycle,zone])
		var row:={"cycle":cycle,"zone":zone,"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"vram":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"materials":EIFigure._materials.size(),"meshes":EIFigure._meshes.size(),"worker":s.local_host.frontend,"old_world_freed":previous==null or previous.get_ref()==null}
		rows.append(row);print("RELOAD_SAMPLE ",JSON.stringify(row));_persist()
	await s.local_host.stop();g.queue_free();s.queue_free()
	for i in 8:await get_tree().process_frame
	TexUpscale.shutdown();_persist()
	print("DESCRIPTOR_RELOAD ",rows.size()," loads ",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
