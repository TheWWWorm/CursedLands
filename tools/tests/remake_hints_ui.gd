extends "third_person_kbm.gd"
## Records the actual drawn shortcut strings, with an original campaign loaded.
class RecordedReticle extends DirectControl.Reticle:
	var hints: Array[String]=[]
	func _draw() -> void:
		hints.clear(); super._draw()
	func _draw_hint(font:Font,text:String,y:float,k:float,colour:=Interface800.TEXT,backing:=true) -> void:
		hints.append(text); super._draw_hint(font,text,y,k,colour,backing)

func frames(n:=4) -> void:
	for i in n:
		await get_tree().process_frame
		if is_instance_valid(g): g.rig._window_focused=true

func capture(label:String) -> void:
	await frames(4); await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://hints-"+label+".png")

func _ready() -> void:
	await frames(8)
	check(GameData.option("hide_remake_hints")==0,"extra hints are shown in a fresh profile")
	check(GameData.option("enemy_hp_bars")==EnemyBars.ALWAYS,"fresh HP bar preference is Always")
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":0,"pad_enabled":0,"confine_mouse":0},true)
	GameData._window_gen+=1; get_window().mode=Window.MODE_WINDOWED
	get_window().size=Vector2i(1280,800); get_window().position=Vector2i.ZERO; get_window().grab_focus()
	PadInput.active="kbm"; TouchInput.enabled=false
	s=Session.new(); add_child(s); g=Game.new(); g.session=s; s.game=g; add_child(g)
	s.state.ensure_hero(0,"Human Hero"); await s.enter_zone("gz1g",1,false)
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false); s.world.vm.instances.clear()
	hero=s.party_units(0)[0]; g.selected.assign([hero]); g.rig.release(); g.hud._dialog.hide(); await frames(12)
	g.rig.set_process(false); g.direct.set_process(false)
	var old:=g.direct._overlay; var reticle:=RecordedReticle.new()
	reticle.controls=g.direct; reticle.mouse_filter=Control.MOUSE_FILTER_IGNORE
	old.get_parent().add_child(reticle); reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.direct._overlay=reticle; old.queue_free(); await frames(3)
	var camera_key:=g.direct.key_label("tactical")
	var wiki_key:=EIKeymap.key_of("wiki_context")
	for language in ["en","ru","de"]:
		RemakeText.lang=language
		for view in [0,2,3]:
			GameData.options.control_mode=view; GameData.options.hide_remake_hints=0
			g.direct._tactical_return=false; g.direct._process(0); await frames(4)
			check(reticle.visible and reticle.hints.any(func(t):return camera_key in t and wiki_key in t),"camera/wiki guide draws on initial view %d in %s"%[view,language])
			await capture(language+"-view-"+str(view))
			GameData.options.hide_remake_hints=1; g.direct._process(0); await frames(4)
			check(not reticle.visible or not reticle.hints.any(func(t):return camera_key in t or wiki_key in t),"hide option suppresses guides in view %d"%view)
			if view>0: check(reticle.visible,"hide option keeps direct crosshair active")
		# Settings label, both choices, help and cancel/save behavior.
		g.direct._capture(false); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		var panel:=OptionsPanel.new(); add_child(panel); panel.open(); panel._tutorial.visible=false
		panel._show_group(OptionsPanel.INTERFACE_GROUP); panel._sel=9; await frames(5)
		var row: Dictionary=panel._rows[9]
		check(row.name=="hide_remake_hints" and row.label==RemakeText.t("Hide remake hints"),"new option label in "+language)
		check(row.choices==RemakeText.tl(["Off","On"]),"new option choices in "+language)
		check(row.tip.contains(RemakeText.t(GameData.REMAKE_OPTIONS.hide_remake_hints[1])),"new option help in "+language)
		check(panel.text_width(row.label,1)<=260,"option label fits in "+language)
		await capture(language+"-settings")
		panel._restore(); panel._close(); panel.queue_free(); await frames(3)
	# Guides follow the actual bindings in both tactical and direct modes.
	var classic:=EIKeymap.bindings(); var direct:=EIKeymap.bindings(2)
	var rebound:=classic.duplicate()
	for key in rebound.keys():
		if rebound[key]=="wiki_context": rebound.erase(key)
	rebound[EIKeymap.scan_code(KEY_F9)]="wiki_context"; EIKeymap.set_bindings(rebound)
	rebound=direct.duplicate()
	for key in rebound.keys():
		if rebound[key]=="direct_tactical": rebound.erase(key)
	rebound[EIKeymap.scan_code(KEY_F8)]="direct_tactical"; EIKeymap.set_bindings(rebound,2)
	for view in [0,2,3]:
		GameData.options.control_mode=view; GameData.options.hide_remake_hints=0; g.direct._process(0); await frames(4)
		check(reticle.hints.any(func(t):return "F8" in t and "F9" in t),"guide follows rebound shortcuts in view %d"%view)
	EIKeymap.set_bindings(classic); EIKeymap.set_bindings(direct,2)
	# Existing preferences retain their values when settings are saved.
	GameData.options.enemy_hp_bars=0; GameData.options.hide_remake_hints=1; GameData.save_settings()
	var config:=ConfigFile.new(); config.load(GameData.CONFIG_PATH)
	check(config.get_value("options","enemy_hp_bars")==0 and config.get_value("options","hide_remake_hints")==1,"explicit HP-bar and hide-hint preferences persist")
	g.queue_free(); s.queue_free(); await frames(10); TexUpscale.shutdown()
	print("REMAKE_HINTS_UI ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
