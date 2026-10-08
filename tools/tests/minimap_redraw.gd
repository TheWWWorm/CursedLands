extends Node
## Compare the retained heading layer with the former single-item draw path.
var checks := 0
var failures := 0

class Reference extends Minimap:
	func _ready() -> void:
		super._ready()
		_heading_layer.hide()
	func _draw() -> void:
		super._draw()
		if _tex:
			var h := _heading()
			_arrow(HudDial.arrow(694 + _off, 84, atan2(h.x, h.y), 0.8), true)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _ready() -> void:
	var w := GameWorld.new()
	w.zone = {"id":"redraw-test", "exits":{"one":{"to":"next", "area":Rect2(260,260,3,3)}}}
	var g := Game.new()
	var session := Session.new()
	g.session = session
	g.world = w
	session.world = w
	w.session = session
	var hero := GameUnit.new()
	hero.pos = Vector2(256,256)
	g.selected.assign([hero])
	var pic := Image.create(64,64,false,Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			pic.set_pixel(x,y,Color(float(x)/64.0,float(y)/64.0,0.3 if (x/8+y/8)%2 else 0.6,1))
	var tex := ImageTexture.create_from_image(pic)
	var views: Array[SubViewport] = []
	var maps: Array[Minimap] = []
	var cams: Array[Camera3D] = []
	var draws := [0,0]
	var heading_draws := [0]
	for i in 2:
		var view := SubViewport.new()
		view.size = Vector2i(600,600)
		view.own_world_3d = true
		view.transparent_bg = true
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(view)
		var cam := Camera3D.new()
		view.add_child(cam)
		cam.make_current()
		var map: Minimap = Minimap.new() if i == 0 else Reference.new()
		map.game = g
		view.add_child(map)
		map.set_process(false)
		map._zone = "redraw-test"
		map._tex = tex
		map._size = Vector2(512,512)
		map._l = 512
		map.draw.connect(func():draws[i]+=1)
		if i == 0: map._heading_layer.draw.connect(func():heading_draws[0]+=1)
		views.append(view); maps.append(map); cams.append(cam)
	for trial in 24:
		for i in 2:
			views[i].size = Vector2i(600 if trial<12 else 900,600 if trial<12 else 900)
			cams[i].rotation = Vector3(-0.8,trial*TAU/12.0,0)
			maps[i].zoom = 1.0+float(trial%3)
			maps[i].open = trial%4 != 1
			maps[i]._p = float(trial%4)/3.0
			maps[i]._process(0.0)
			maps[i]._off = float(trial%4)*60.0
			maps[i]._process(0.0)
			maps[i].queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var actual := views[0].get_texture().get_image()
		var expected := views[1].get_texture().get_image()
		check(actual.get_data()==expected.get_data(),"same rendered pixels: heading/zoom/slide/scale %d"%trial)
		if trial==0 or failures:
			actual.save_png("user://minimap-retained-%02d.png"%trial)
			expected.save_png("user://minimap-reference-%02d.png"%trial)
	# With no map tick due, a new camera heading must redraw only the arrow.
	maps[0].open = true
	maps[0]._p = 0.0
	maps[0]._off = 0.0
	maps[0]._process(0.0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	maps[0]._redraw_t = 1.0
	var before: int = draws[0]
	var arrow_before: int = heading_draws[0]
	cams[0].rotation.y += 0.3
	maps[0]._process(0.0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(draws[0]==before,"camera rotation retains map/frame commands")
	check(heading_draws[0]>arrow_before,"camera arrow updates in the same rendered frame")
	check(maps[0]._heading_layer.mouse_filter==Control.MOUSE_FILTER_IGNORE,"heading does not intercept map clicks")
	maps[0].hide()
	check(not maps[0]._heading_layer.is_visible_in_tree(),"hiding the minimap hides the heading")
	maps[0].show()
	check(maps[0]._heading_layer.is_visible_in_tree(),"showing the minimap restores the heading")
	for view in views:view.free()
	hero.free();g.free();session.world=null;session.free();w.session=null;w.free()
	print("MINIMAP_REDRAW ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
