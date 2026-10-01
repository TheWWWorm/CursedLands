class_name LoadingScreen
extends CanvasLayer
## Zone loading screen: the original picks Movies\progres*.bik by the
## zone's allod (progres2 Gipat, progres3 Ingos, progres4 Suslanger, else
## progres; progres1 for gz1g and bz7g) and plays it on its own
## thread, looping at 15 fps, letterboxed, until the load is done. The remake
## builds zones on the main thread, so the build calls `tick()` between steps;
## each tick shows the frame due and draws the screen at most every 1/15 s.
## Approx.: the movie shows only once its conversion is cached (converted in
## the background from the main menu); before that the screen stays black.

const FRAME := 1.0 / 15.0

static var _current: LoadingScreen
var _player: MoviePlayer
var _last := 0
var _canvas: RID
var _item: RID    # black backdrop
var _frame: RID   # the movie frame (YUV shader)


static func movie_for(zone: Dictionary) -> String:
	var id := String(zone.get("id", ""))
	if id in ["gz1g", "bz7g"]:
		return "progres1"
	return {"gipat": "progres2", "ingos": "progres3", "suslanger": "progres4"}.get(
		String(zone.get("allod", "")).to_lower(), "progres")


const MOVIES := ["progres", "progres1", "progres2", "progres3", "progres4"]


static func begin(tree: SceneTree, zone: Dictionary) -> void:
	end()
	if DisplayServer.get_name() == "headless":
		return
	if Engine.get_process_frames() == 0:
		return   # called from a _ready during scene setup: the root is busy adding children
	var ls := LoadingScreen.new()
	ls.visible = false   # drawn through the RenderingServer below
	tree.root.add_child(ls)
	# The MoviePlayer only decodes here: while the main thread builds the zone
	# no Control redraw is flushed, so the frame is drawn with RenderingServer
	# calls, which take effect at the next force_draw.
	ls._player = MoviePlayer.new()
	ls._player.loop = true
	ls._player.silent = true
	ls.add_child(ls._player)
	ls._player.play_cached(movie_for(zone))
	var rs := RenderingServer
	ls._canvas = rs.canvas_create()
	var vp := tree.root.get_viewport_rid()
	rs.viewport_attach_canvas(vp, ls._canvas)
	rs.viewport_set_canvas_stacking(vp, ls._canvas, 1000, 0)
	ls._item = rs.canvas_item_create()
	rs.canvas_item_set_parent(ls._item, ls._canvas)
	ls._frame = rs.canvas_item_create()
	rs.canvas_item_set_parent(ls._frame, ls._item)
	rs.canvas_item_set_material(ls._frame, ls._player._mat.get_rid())
	_current = ls
	ls._last = Time.get_ticks_msec()
	ls._draw_frame()


## Called by the zone build between steps.
static func tick() -> void:
	var ls := _current
	if ls == null:
		return
	var now := Time.get_ticks_msec()
	var dt := (now - ls._last) / 1000.0
	if dt < FRAME:
		return
	ls._last = now
	ls._player.step(dt)
	ls._draw_frame()


static func end() -> void:
	var ls := _current
	_current = null
	if ls and is_instance_valid(ls):
		RenderingServer.free_rid(ls._frame)
		RenderingServer.free_rid(ls._item)
		RenderingServer.free_rid(ls._canvas)
		ls.queue_free()


## Black screen with the current frame letterboxed (aspect kept), then a draw.
func _draw_frame() -> void:
	var rs := RenderingServer
	var screen := get_viewport().get_visible_rect().size
	rs.canvas_item_clear(_item)
	rs.canvas_item_clear(_frame)
	rs.canvas_item_add_rect(_item, Rect2(Vector2.ZERO, screen), Color.BLACK)
	var tex: Texture2D = _player._tex[0]
	if tex and _player._tex[1] and _player._tex[2]:
		var ts := Vector2(tex.get_size())
		var k := minf(screen.x / ts.x, screen.y / ts.y)
		var r := Rect2((screen - ts * k) * 0.5, ts * k)
		rs.canvas_item_add_texture_rect(_frame, r, tex.get_rid())
	rs.force_draw(true, 0.0)
