class_name EscSignpost
extends SubViewportContainer
## The original in-game Esc menu: the small carved signpost (menus.res
## "unmoco1", textures escmenu00 / escmenu00labels) drawn over the game.
## Its boards are the buttons; clicking one emits `pressed` (click handler
##  plays buttons\menu\ok.wav for any board).
## Animations (unmoco1.anm; (k) plays uspecial k + 1 through
## ): opening uspecial02, the post
## rising into place; hovering a board turns it: save
## uspecial03, load 04, options 05, return2game 06, exit2mainmenu 07 (held on
## the last frame); off the boards goes back to cidle.

signal pressed(action: String)

const BOARDS := {"save": "save", "load": "load", "options": "options", "return2game": "resume",
	"exit2mainmenu": "exit"}
## board -> its argument (uspecial number - 1), by the
## menus.reg [EscMenu] index: 0 SaveGame 2, 1 LoadGame 3, 2 ResumeGame 5,
## 3 ExitMM 6, 4 Options 4.
const HOVER_ANIM := {"save": 2, "load": 3, "return2game": 5, "exit2mainmenu": 6, "options": 4}

var _vp: SubViewport
var _cam: Camera3D
var _post: Node3D
var _player: AnimationPlayer
var _boards := {}
var _board_meshes := {}
var _framed := false


func _ready() -> void:
	# The game is paused under the Esc menu (single player): the signpost, its
	# SubViewport and AnimationPlayer keep running.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pad_panel")   # remake: gamepad snap targets (PadUI)
	visibility_changed.connect(func():
		if visible:
			_on_open())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	add_child(_vp)
	_post = EIFigure.instantiate("unmoco1", "escmenu00", Vector3(0.5, 0.5, 0.5))
	if _post == null:
		return
	_vp.add_child(_post)
	var labels := EIFigure.material_for("escmenu00labels")
	for mi: MeshInstance3D in _post.find_children("*", "MeshInstance3D", true, false):
		if String(mi.get_parent().name).ends_with("label"):
			mi.material_override = labels
	for part: String in BOARDS:
		var n := _post.find_child(part, true, false) as Node3D
		if n:
			_boards[part] = n
			_board_meshes[part] = n.find_children("*", "MeshInstance3D", true, false)
			# The caption is a sibling mesh filling the carved board's hole.
			# Include it so tapping the visible text activates the same board.
			var label := _post.find_child(part + "label", true, false)
			if label:
				_board_meshes[part].append_array(label.find_children("*", "MeshInstance3D", true, false))
	var paths := {}
	for n: Node in _post.find_children("*", "Node3D", true, false):
		if not n is MeshInstance3D:
			paths[String(n.name)] = _post.get_path_to(n)
	_player = AnimationPlayer.new()
	_post.add_child(_player)
	_player.root_node = NodePath("..")
	# The figure's root part is escmenu00 (unmoco1.lnk); only the root's
	# translation keys move it, which is the open slide.
	_player.add_animation_library("ei", EIAnim.library("unmoco1", paths, "escmenu00"))
	_play("cidle")
	_cam = Camera3D.new()
	# This UI camera is positioned outside physics ticks, including while the
	# game is paused. Picking must use that same pose rather than an old
	# interpolated transform cached by the SubViewport.
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_cam.fov = 40.0
	_vp.add_child(_cam)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, 20, 0)
	_vp.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	_vp.add_child(env)
	_frame()


func _process(_dt: float) -> void:
	_frame()


## Frames the signpost once, at its rest pose (before any opening slide).
func _frame() -> void:
	if _framed or _post == null or _cam == null or not _post.is_inside_tree():
		return
	_framed = true
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in _post.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var c := box.get_center()
	var r := box.size.y * 0.5
	var eye := c + Vector3(0, 0, r / tan(deg_to_rad(20.0)) * 1.15)
	_cam.transform = Transform3D(Basis.looking_at(c - eye), eye)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		# a newly hovered board sounds buttons\menu\stone.wav and
		# turns (its uspecial); off the boards plays the idle.
		var hb := board_at(e.position)
		if hb != _hover_board:
			_hover_board = hb
			if hb:
				_sfx("buttons\\menu\\stone.wav")
				_play("uspecial%02d" % (HOVER_ANIM[hb] + 1))
			else:
				_play("cidle")
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var b := board_at(e.position)
		if b:
			_sfx("buttons\\menu\\ok.wav")
			pressed.emit(BOARDS[b])
		accept_event()


var _hover_board := ""


## the signpost opens with buttons\menu\shift.wav and
## (1), uspecial02 (the post rises from below, 12 frames).
func _on_open() -> void:
	GameData.trace("esc menu open")
	_frame()
	_hover_board = ""
	_sfx("buttons\\menu\\shift.wav")
	_play("uspecial02")
	# The SubViewport still holds its last picture (the rest pose) on the
	# first visible frame; keep it transparent until the slide has rendered.
	self_modulate.a = 0.0
	await RenderingServer.frame_post_draw
	self_modulate.a = 1.0


func _play(anim: String) -> void:
	if _player and _player.has_animation("ei/" + anim):
		_player.play("ei/" + anim)
		_player.advance(0.0)


func _sfx(path: String) -> void:
	var click := AudioStreamPlayer.new()
	click.bus = "SFX"
	click.stream = EIAudio.sfx(path)
	add_child(click)
	click.play()
	click.finished.connect(click.queue_free)


## The board under a point: the nearest board triangle on the camera ray.
## The original hit-tests menus.reg [EscMenu] rectangles (800×600)
## against its own view of the signpost; the remake frames the signpost
## itself (see _process), so it picks the boards' geometry instead
## (**Approx.**; the earlier screen-box test let neighbouring boards' boxes
## overlap).
func board_at(p: Vector2) -> String:
	var scale := Vector2(_vp.size) / size if size.x > 0 else Vector2.ONE
	p *= scale
	if _cam == null:
		return ""
	var o := _cam.project_ray_origin(p)
	var d := _cam.project_ray_normal(p)
	var best := ""
	var bt := INF
	for part: String in _boards:
		for mi: MeshInstance3D in _board_meshes[part]:
			if mi.mesh == null:
				continue
			var f := mi.mesh.get_faces()
			var xf := mi.global_transform
			for i in range(0, f.size() - 2, 3):
				var hit = Geometry3D.ray_intersects_triangle(o, d, xf * f[i], xf * f[i + 1], xf * f[i + 2])
				if hit != null and o.distance_to(hit) < bt:
					bt = o.distance_to(hit)
					best = part
	return best


func _unhandled_key_input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		_sfx("buttons\\menu\\ok.wav")   # Esc (0x1b) plays ok.wav and closes
		pressed.emit("resume")
		get_viewport().set_input_as_handled()


## Remake (gamepad, BG3's menu shortcuts): Y = quick save, X held = quick
## load (`pressed` "quicksave" / "quickload", GameHUD._on_esc_board).
func pad_press(action: String, phase: String) -> bool:
	match action:
		"pause":
			if phase == "down":
				pressed.emit("quicksave")
			return true
		"context":
			if phase == "hold":
				pressed.emit("quickload")
			return true
	return false


## Extra snap targets beside the signpost (the co-op host's Players button),
## set by GameHUD: [{rect, id}] in viewport pixels.
var pad_extra: Callable


## Remake (gamepad, PadUI): each board's screen rectangle, from its meshes
## projected through the signpost's camera.
func pad_targets() -> Array:
	var out: Array = []
	if _cam == null or _vp == null or size.x <= 0.0:
		return out
	var to_ctrl := size / Vector2(_vp.size)
	var xf := get_global_transform_with_canvas()
	for part: String in _boards:
		var r := Rect2()
		var first := true
		for mi: MeshInstance3D in _board_meshes[part]:
			var b: AABB = mi.global_transform * mi.get_aabb()
			for i in 8:
				var c := b.get_endpoint(i)
				if _cam.is_position_behind(c):
					continue
				var sp := xf * (_cam.unproject_position(c) * to_ctrl)
				r = Rect2(sp, Vector2.ZERO) if first else r.expand(sp)
				first = false
		if not first:
			out.append({"rect": r, "id": BOARDS[part]})
	if pad_extra.is_valid():
		out.append_array(pad_extra.call())
	return out
