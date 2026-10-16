extends "capture.gd"
## Loaded only against the separately pinned Trials of Gipath preview pack.
var screen: Control

func _run() -> void:
	seed(int(spec.get("seed",6519)))
	_apply_ultra()
	GameData.options.merge({"autosave":0,"auto_graphics":0,"show_tutorial":0,"confine_mouse":0,"vsync":0,"fps_limit":0,
		"render_scale":4,"q_aa":3,"q_shadows":3,"volume_stream":0,"volume_sfx":85},true)
	RemakeText.lang=language
	GameData._apply_audio()
	GameData.options_changed.emit()
	await frames(20)
	GameData._window_gen+=1
	get_tree().root.mode=Window.MODE_WINDOWED
	get_tree().root.size=Vector2i(int(spec.get("width",3840)),int(spec.get("height",2160)))
	Input.mouse_mode=Input.MOUSE_MODE_HIDDEN
	screen=load("res://src/ui/arena_pve_screen.gd").new()
	add_child(screen)
	await frames(30)
	screen._seed_input.text="6519"
	screen._begin(0)
	screen.run.auto_save=false
	screen.run.wave=18
	screen.run.pact="vanguard"
	screen.run.pact_rank=2
	screen.run.army.clear()
	var rules=load("res://src/game/arena_rules.gd")
	for family in 6: screen.run._recruit(family,rules.FAMILIES[family].forms.size()-1,27)
	screen.run.arrange()
	screen._clear_selection()
	await frames(90)
	screen.field.zoom=21
	screen.field._update_camera()
	screen._start.pressed.emit()
	await frames(45)
	await RenderingServer.frame_post_draw
	var picture:=get_viewport().get_texture().get_image()
	picture.save_png(out+"-start.png")
	if probe:get_tree().quit();return
	total=int(spec.frames)
	first_frame=Engine.get_frames_drawn()
	report={"id":spec.id,"start_frame":first_frame,"frames":total,"fps":60,"width":picture.get_width(),"height":picture.get_height(),
		"campaign":GameData.campaign_id,"language":language,"seed":6519,"renderer":RenderingServer.get_current_rendering_method(),
		"engine":Engine.get_version_info(),"staged":true,"preview_mode":true,"graphics":_graphics_report()}
	recording=true
	print("TRAILER_START ",JSON.stringify(report))

func _camera(t: float) -> void:
	if screen:
		screen.field.yaw=-0.10+t*0.16
		screen.field._update_camera()
