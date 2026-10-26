extends "contextual_tutorials.gd"
## Actual field HUD at desktop resolutions, including Cyrillic and German.
## Captures retain native pixels. Book padding is measured from those pixels.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_render_loop_enabled(true)
	Engine.max_fps=30
	TutorialPanel.persist = false; TutorialProgress.persist = false
	GameData.options.merge({"autosave":0,"show_tutorial":1,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"control_mode":0,"confine_mouse":0,"show_fps":1,
		"volume_sfx":0,"volume_stream":0,"volume_voice":0,"display_mode":0},true)
	s = Session.new(); add_child(s)
	g = Game.new(); g.session=s; s.game=g; add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("gz1g",1,false)
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	hero=s.party_units(0)[0];g.selected.assign([hero]);g.rig.release()
	await frames(8)
	g.rig.set_process(false);g.direct.set_process(false)
	hint=g.hud._tutorial;hint.set_process(false)
	get_window().wrap_controls=false;get_window().min_size=Vector2i.ONE
	get_window().mode=Window.MODE_WINDOWED;get_window().borderless=true
	for resolution: Vector2i in [Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160)]:
		get_window().size=resolution;await frames(6)
		for language: String in ["en","ru","de"]:
			RemakeText.lang=language
			fresh();hint._present("zt23",true);hint._process(0.1);await frames(5);hint._process(0.1)
			var tag := "%s-%dx%d"%[language,resolution.x,resolution.y]
			var rect := hint._card.get_global_rect()
			check(Rect2(Vector2.ZERO,Vector2(resolution)).encloses(rect),"complete expanded hint fits "+tag)
			for label: Label in [hint._heading,hint._body,hint._details]:
				check(label.get_visible_line_count()==label.get_line_count(),"localized text is not clipped "+tag)
				var sampled := false
				var parent: Node=label
				while parent is CanvasItem:
					if parent.oversampling_with_scale!=CanvasItem.OVERSAMPLING_WITH_SCALE_PARENT_NODE:
						sampled=parent.oversampling_with_scale==CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED;break
					parent=parent.get_parent()
				check(sampled or label.get_theme_font("font").is_multichannel_signed_distance_field(),"text rasterization follows displayed scale "+tag)
			check(hint._book.icon.get_width()>=hint._book.get_theme_constant("icon_max_width"),"book source resolves displayed pixels "+tag)
			await RenderingServer.frame_post_draw
			var glyphs_at_scale := false
			for rid: RID in hint._body.get_theme_font("font").get_rids():
				for cache: Dictionary in TextServerManager.get_primary_interface().font_get_size_cache_info(rid):
					if float(cache.get("viewport_oversampling",1.0)) >= hint._card.scale.x-0.02 and int(cache.glyphs)>0:
						glyphs_at_scale=true
			if not glyphs_at_scale:
				for rid:RID in hint._body.get_theme_font("font").get_rids():print("GLYPH_CACHE ",tag," scale=",hint._card.scale.x," ",TextServerManager.get_primary_interface().font_get_size_cache_info(rid))
			check(glyphs_at_scale,"drawn glyph cache resolves display scale "+tag)
			var image:=get_viewport().get_texture().get_image()
			var path:="user://high-resolution-"+tag+".png"
			check(image.save_png(path)==OK,"native resolution capture saved "+tag)
			captures.append(ProjectSettings.globalize_path(path))
			# The open hint can overlap the book. Measure the actual standalone
			# button after closing the card, never the heading's separate icon.
			hint.close();await frames(3);await RenderingServer.frame_post_draw
			image=get_viewport().get_texture().get_image()
			var book:=hint._book.get_global_rect()
			var left:=int(book.end.x);var right:=int(book.position.x)
			for y in range(int(book.position.y+book.size.y*0.2),int(book.end.y-book.size.y*0.2)):
				for x in range(int(book.position.x+2),int(book.end.x-2)):
					var p:=image.get_pixel(x,y)
					if p.r>0.30 and p.g>0.20 and p.r>p.b*1.8:
						left=mini(left,x);right=maxi(right,x)
			check(right>left and absf((left+right+1)*0.5-book.get_center().x)<=1.5,"visible book has symmetric horizontal padding "+tag)
			image.get_region(Rect2i(book)).save_png("user://book-"+tag+".png")
			# Exercise the real button signal and full-guide return path.
			hint._book.pressed.emit();await frames(3)
			check(g.hud._wiki.visible,"book opens readable guide "+tag)
			g.hud._wiki.close();await frames(3)
			if resolution.x==3840:
				hint._present("zt23",false);hint._process(0.1);await frames(3)
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("user://water-hint-"+language+"-4k.png")
	FileAccess.open("user://high-resolution-ui.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures},"\t"))
	if OS.get_cmdline_user_args().has("--record-ui"):await record_ui()
	g.queue_free();s.queue_free();await frames(6)
	print("HIGH_RESOLUTION_UI ",checks," checks ",failures.size()," failures")
	TexUpscale.shutdown();get_tree().quit(1 if not failures.is_empty() else 0)

## Optional native viewport recording, independent of the virtual monitor size.
## Keep capture timestamps so an encoder can preserve actual display timing.
func record_ui() -> void:
	var directory:="user://ui-recording";DirAccess.make_dir_recursive_absolute(directory)
	var recording:=[]
	for language: String in ["en","ru","de"]:
		RemakeText.lang=language
		for state in 3:
			if state==0:fresh();hint._present("zt23",false);hint._process(0.1)
			elif state==1:hint._present("zt23",true);hint._process(0.1)
			else:hint.close();hint._book.pressed.emit()
			for i in 18:
				await get_tree().create_timer(0.10,true).timeout
				await RenderingServer.frame_post_draw
				var file:="frame-%04d.jpg"%recording.size()
				var at:=Time.get_ticks_msec()
				get_viewport().get_texture().get_image().save_jpg(directory.path_join(file),0.98)
				recording.append({"file":file,"ms":at,"language":language,"state":state})
		g.hud._wiki.close()
	FileAccess.open(directory.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify(recording))
