class_name LoadingScreen
extends CanvasLayer
## Zone / save loading screen. the original picks Movies\progres*.bik
## by the zone's allod (progres2 Gipat, progres3 Ingos, progres4 Suslanger,
## else progres; progres1 for gz1g and bz7g). The movie is a 12-frame progress
## picture (800×600, all five files): it is not played but stepped. Each load
## stage (n), which opens the movie on its first call, decodes
## forward up to frame min(n, frames − 1) (never back: a smaller n shows the
## frame already there), blits it to the window and flips once; nothing redraws
## between two calls. closes it at the end of the client's map
## load. The steps (the 14 call sites):
##   server, new zone (CWorldServer::LoadMap): 0, objects 2..5, 6, 7
##   server, saved zone (CWorldServer::LoadSave): 0, 1, objects 2..5, 5, 6, 7
##     (loads a zone already in saves\current with LoadSave, as a
##     save game does:)
##   objects (the.mob loop): after object i of N, when
##     i % (N / 5 + 1) == 0, frame i / (N / 5 + 1) + 1, so 2..5
##   client (net message handler): 8, 9, 10, 11, close
##     a joining peer runs only this part, so its screen starts at frame 8.
## Remake stages (see `step` calls in Session, EIMapScene, GameWorld): the
## remake builds the zone once for server and client, on the main thread, and
## draws each new frame with RenderingServer + force_draw (no Control redraw is
## flushed mid-build). **Approx.** mapping where the stages differ:
##   0 load start · 1 terrain read (saved zone only; LoadSave reads the .mpr
##   before it) · 2..5 map objects and units as the original counts them · 5 objects
##   done (saved zone) · 6 zone state restored · 7 world built · 8 parties
##   deployed · 9 zone scripts started · 10 before the shader warm-up · 11 at the
##   end. The original's client terrain load (between 10 and 11) is part of the
##   remake's terrain step. A joiner: 8 at the start, 9 world built, 10 units
##   received, 11 at the end.
## The frames are decoded with EIBink (12 frames, ~0.5 s in all), so no
## converted movie is needed. Not shown headless or on the web (a browser
## presents only after the current JS callback returns; forced nested draws
## cannot show it and can block WebGL when a network/input callback replaces
## the current scene).

enum {NEW_ZONE, SAVED_ZONE, CLIENT}

static var _current: LoadingScreen
## Tools: called with the frame number after each new frame is drawn.
static var on_frame := Callable()
var _kind := NEW_ZONE
var _bink: EIBink
var _decoded := -1   # last decoded frame
var _objects := 0    # object count N and the count so far
var _object_i := 0
var _mat: ShaderMaterial
var _tex: Array[ImageTexture] = [null, null, null]
var _canvas: RID
var _item: RID    # black backdrop
var _frame: RID   # the movie frame (YUV shader)


static func movie_for(zone: Dictionary) -> String:
	var id := String(zone.get("id", ""))
	if id in ["gz1g", "bz7g"]:
		return "progres1"
	return {"gipat": "progres2", "ingos": "progres3", "suslanger": "progres4"}.get(
		String(zone.get("allod", "")).to_lower(), "progres")


## Opens the screen for a zone load and shows its first frame (0, a joiner 8).
static func begin(tree: SceneTree, zone: Dictionary, kind := NEW_ZONE) -> void:
	end()
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	if Engine.get_process_frames() == 0:
		return   # called from a _ready during scene setup: the root is busy adding children
	if GameData.root.is_empty():
		return
	var src := GameData.root.path_join("movies/%s.bik" % movie_for(zone))
	var bink := EIBink.new()
	if not GameFiles.exists(src) or not bink.open(src):
		return   #  only logs "Can't open video file" and draws nothing
	var ls := LoadingScreen.new()
	ls.visible = false   # drawn through the RenderingServer below
	ls._kind = kind
	ls._bink = bink
	tree.root.add_child(ls)
	ls._mat = ShaderMaterial.new()
	ls._mat.shader = Shader.new()
	ls._mat.shader.code = MoviePlayer.SHADER
	var rs := RenderingServer
	ls._canvas = rs.canvas_create()
	var vp := tree.root.get_viewport_rid()
	rs.viewport_attach_canvas(vp, ls._canvas)
	rs.viewport_set_canvas_stacking(vp, ls._canvas, 1000, 0)
	ls._item = rs.canvas_item_create()
	rs.canvas_item_set_parent(ls._item, ls._canvas)
	ls._frame = rs.canvas_item_create()
	rs.canvas_item_set_parent(ls._frame, ls._item)
	rs.canvas_item_set_material(ls._frame, ls._mat.get_rid())
	_current = ls
	ls._show(8 if kind == CLIENT else 0)


## (n) at a load stage. A joiner starts at frame 8, so the server
## part's frames (1..7) change nothing there.
static func step(frame: int) -> void:
	if _current:
		_current._show(frame)


## The .mpr has been read: LoadSave shows frame 1 here.
static func map_read() -> void:
	if _current and _current._kind == SAVED_ZONE:
		_current._show(1)


## the.mob objects (units included) about to be made.
static func objects(count: int) -> void:
	if _current:
		_current._objects = count
		_current._object_i = 0


## one object made.
static func object_done() -> void:
	var ls := _current
	if ls == null:
		return
	ls._object_i += 1
	var per := ls._objects / 5 + 1
	if ls._object_i % per == 0:
		ls._show(ls._object_i / per + 1)


## All objects made: LoadSave shows frame 5 after reading their saved state.
static func objects_done() -> void:
	if _current and _current._kind == SAVED_ZONE:
		_current._show(5)


## Last frame (11), then the screen goes.
static func end() -> void:
	var ls := _current
	if ls and is_instance_valid(ls):
		ls._show(11)
	_current = null
	if ls and is_instance_valid(ls):
		RenderingServer.free_rid(ls._frame)
		RenderingServer.free_rid(ls._item)
		RenderingServer.free_rid(ls._canvas)
		ls.queue_free()


## Decodes forward to `frame` (clamped to the last one) and draws it; an
## earlier frame keeps the one shown.
func _show(frame: int) -> void:
	frame = mini(frame, _bink.frame_count - 1)
	if frame <= _decoded:
		return
	while _decoded < frame:
		_decoded += 1
		if not _bink.decode_frame(_bink.frame_data(_decoded)):
			return
	var planes := StartupScreen.planes(_bink)
	for i in 3:
		if _tex[i] and Vector2i(_tex[i].get_size()) == planes[i].get_size():
			_tex[i].update(planes[i])
		else:
			_tex[i] = ImageTexture.create_from_image(planes[i])
	_mat.set_shader_parameter("u_tex", _tex[1])
	_mat.set_shader_parameter("v_tex", _tex[2])
	_draw_frame()
	if on_frame.is_valid():
		on_frame.call(_decoded)


## Black screen with the frame letterboxed (aspect kept), then a draw.
func _draw_frame() -> void:
	var rs := RenderingServer
	var screen := get_viewport().get_visible_rect().size
	rs.canvas_item_clear(_item)
	rs.canvas_item_clear(_frame)
	rs.canvas_item_add_rect(_item, Rect2(Vector2.ZERO, screen), Color.BLACK)
	var ts := Vector2(_tex[0].get_size())
	var k := minf(screen.x / ts.x, screen.y / ts.y)
	rs.canvas_item_add_texture_rect(_frame, Rect2((screen - ts * k) * 0.5, ts * k), _tex[0].get_rid())
	rs.force_draw(true, 0.0)
