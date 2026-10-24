extends Node
const Device = preload("res://src/game/fx/scene_raytrace_device.gd")
var checks:=0
var failures:=[]
var out:="user://scene-rt-options"
func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func frames(n:=3) -> void:
	for i in n:await get_tree().process_frame
func key(panel: OptionsPanel,value: Key) -> void:
	var event:=InputEventKey.new();event.keycode=value;event.pressed=true;panel._unhandled_key_input(event)
func _ready() -> void:run.call_deferred()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(GameData.option("rt_shadows")==0 and GameData.option("rt_gi")==0,"fresh profiles keep scene RT opt in")
	check(GameData.option("q_rt_lighting")==1,"fresh profiles default RT lighting to Medium")
	check(GameData.option("pt_mode")==0 and GameData.option("pt_accumulation")==0,"path tracing is opt in with responsive history")
	var panel:=OptionsPanel.new();add_child(panel);panel.open();panel._show_group(OptionsPanel.SCENE_RT_GROUP)
	check(panel._rows[2].disabled,"quality disabled while both lighting effects are off")
	panel._sel=2;key(panel,KEY_LEFT)
	check(panel._values.q_rt_lighting==1,"disabled quality ignores keyboard adjustment")
	if Device.supported():
		panel._sel=0;key(panel,KEY_RIGHT)
		check(panel._values.rt_shadows==1 and GameData.option("rt_shadows")==0,"RT shadow selection is pending until Apply")
		check(not panel._rows[2].disabled,"pending shadow selection enables quality")
		panel._set_value("rt_gi",1);panel._set_value("q_rt_lighting",2);panel._accept()
		var settings:=ConfigFile.new();var ok:=settings.load(GameData.CONFIG_PATH)==OK
		check(ok and settings.get_value("options","rt_shadows",-1)==1 and settings.get_value("options","rt_gi",-1)==1 and settings.get_value("options","q_rt_lighting",-1)==2,"Apply persists all RT choices to isolated profile")
		panel.open();panel._show_group(OptionsPanel.SCENE_RT_GROUP)
		check(panel._values.rt_shadows==1 and panel._values.rt_gi==1 and panel._values.q_rt_lighting==2,"reopening restores saved RT choices")
		panel._set_value("q_rt_lighting",0);panel._restore();panel._close();panel.open();panel._show_group(OptionsPanel.SCENE_RT_GROUP)
		check(panel._values.q_rt_lighting==2,"Cancel restores saved RT quality")
		panel._set_value("pt_mode",1);panel._set_value("pt_accumulation",1)
		check(panel._rows[0].disabled and panel._rows[1].disabled and not panel._rows[2].disabled and not panel._rows[4].disabled,"pending path mode replaces RT controls and enables shared quality and accumulation")
		check(GameData.option("pt_mode")==0,"path selection is pending until Apply")
		panel._accept();settings.load(GameData.CONFIG_PATH)
		check(settings.get_value("options","pt_mode",-1)==1 and settings.get_value("options","pt_accumulation",-1)==1 and settings.get_value("options","rt_shadows",-1)==1 and settings.get_value("options","rt_gi",-1)==1,"Apply persists path options and preserves RT preferences")
		panel.open();panel._show_group(OptionsPanel.SCENE_RT_GROUP)
		check(panel._values.pt_mode==1 and panel._values.pt_accumulation==1,"reopening restores path options")
		panel._set_value("pt_mode",2);panel._restore();panel._close();panel.open();panel._show_group(OptionsPanel.SCENE_RT_GROUP)
		check(panel._values.pt_mode==1,"Cancel restores the saved bounce count")
		panel._set_value("pt_mode",0)
		check(not panel._rows[0].disabled and not panel._rows[1].disabled and panel._rows[4].disabled,"turning path mode off restores RT controls")
	else:
		for row in 5:check(panel._rows[row].disabled,"unsupported renderer disables RT control "+str(row))
		panel._sel=0;key(panel,KEY_RIGHT)
		check(panel._values.rt_shadows==0,"unsupported renderer cannot enable RT")
		panel._values.rt_shadows=1;panel._show_group(OptionsPanel.SCENE_RT_GROUP)
		check(not panel._rows[0].disabled,"unsupported renderer still permits disabling a saved RT choice")
		panel._sel=0;key(panel,KEY_LEFT)
		check(panel._values.rt_shadows==0,"saved unsupported RT choice can be turned off")
		panel._values.pt_mode=1;panel._show_group(OptionsPanel.SCENE_RT_GROUP)
		check(not panel._rows[3].disabled,"unsupported renderer permits disabling saved path mode")
		panel._sel=3;key(panel,KEY_LEFT)
		check(panel._values.pt_mode==0,"saved unsupported path mode can be turned off")
	panel._close();panel.queue_free();await frames()
	for size: Vector2i in [Vector2i(1280,720),Vector2i(800,600)]:
		get_window().borderless=true;get_window().size=size
		await get_tree().create_timer(0.3,true,false,true).timeout
		for language: String in ["en","ru","de"]:
			RemakeText.lang=language
			panel=OptionsPanel.new();add_child(panel);panel.open();panel._show_group(OptionsPanel.REMAKE_GROUP)
			check(panel._rows.size()<=14,"Remake sections fit the fixed grid")
			var link:=OptionsPanel.SECTIONS.find(OptionsPanel.SCENE_RT_GROUP)
			check(link>=0 and panel._rows[link].to==OptionsPanel.SCENE_RT_GROUP,"RT/PT is directly reachable under Remake")
			check(panel.text_width(panel._rows[link].label)<=420.0,"translated RT/PT section fits "+language)
			panel._sel=link;key(panel,KEY_ENTER)
			check(panel._group==OptionsPanel.SCENE_RT_GROUP and panel._parent(panel._group)==OptionsPanel.REMAKE_GROUP,"keyboard opens RT/PT under Remake")
			check(panel.text_width(panel._group_label(panel._group),2)<=600.0,"translated RT/PT breadcrumb fits "+language)
			for row in 5:
				var option: Dictionary=panel._rows[row]
				check(panel.text_width(option.label)<=260.0,"translated label fits "+language+str(row)+str(size))
				for choice in option.choices.size():
					panel._values[option.name]=choice
					check(panel._switch_text(option)==GameData.option_choices(option.name)[choice],"dynamic RT choice resolves "+language+str(row)+str(choice))
					check(panel.text_width(panel._switch_text(option))<=160.0,"translated choice fits "+language+str(row)+str(choice))
				if language!="en":check(option.choices!=GameData.DISPLAY_CHOICES[option.name],"choices translated "+language+str(row))
				get_window().grab_focus();GameData._tips.delay=0.1
				Input.warp_mouse(Vector2(20,20));await frames()
				var at:=panel.p8(Vector2(400,panel._row_y(row)+12))
				Input.warp_mouse(at);var motion:=InputEventMouseMotion.new();motion.position=at;Input.parse_input_event(motion)
				await get_tree().create_timer(0.4,true,false,true).timeout
				check(GameData._tips._panel.visible and GameData._tips._text.contains(RemakeText.t(GameData.REMAKE_OPTIONS[option.name][1])),"translated RT help opens "+language+str(row))
				check(Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size).encloses(Rect2(GameData._tips._panel.position,GameData._tips._panel.size)),"RT help stays inside window "+language+str(row)+str(size))
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(out.path_join("help-%s-%dx%d-%d.png"%[language,size.x,size.y,row]))
				GameData._tips._hide()
			panel._close();panel.queue_free();await frames()
	RemakeText.lang="en"
	FileAccess.open(out.path_join("scene-options.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("SCENE_RT_OPTIONS ",checks," checks ",failures.size()," failures")
	TexUpscale.shutdown();get_tree().quit(1 if not failures.is_empty() else 0)
