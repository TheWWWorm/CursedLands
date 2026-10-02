class_name EscSignpost
extends SubViewportContainer
## The original in-game Esc menu: the small carved signpost (menus.res
## "unmoco1", textures escmenu00 / escmenu00labels) drawn over the game.
## Its boards are the buttons; clicking one emits `pressed` (click handler
##  plays buttons\menu\ok.wav for any board).

signal pressed(action: String)

const BOARDS := {"save": "save", "load": "load", "options": "options", "return2game": "resume",
	"exit2mainmenu": "exit"}

var _vp: SubViewport
var _cam: Camera3D
var _post: Node3D
var _boards := {}
var _board_meshes := {}
var _framed := false


func _ready() -> void:
	visibility_changed.connect(func():   # the signpost opens
		if visible:
			_sfx("buttons\\menu\\shift.wav"))
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
	var player := AnimationPlayer.new()
	_post.add_child(player)
	player.root_node = NodePath("..")
	player.add_animation_library("ei", EIAnim.library("unmoco1", paths, "coloumndetls"))
	if player.has_animation("ei/cidle"):
		player.play("ei/cidle")
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


func _process(_dt: float) -> void:
	if _framed or _post == null or not _post.is_inside_tree():
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
		# a newly hovered board sounds buttons\menu\stone.wav.
		var hb := board_at(e.position)
		if hb != _hover_board:
			_hover_board = hb
			if hb:
				_sfx("buttons\\menu\\stone.wav")
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var b := board_at(e.position)
		if b:
			_sfx("buttons\\menu\\ok.wav")
			pressed.emit(BOARDS[b])
		accept_event()


var _hover_board := ""


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
		pressed.emit("resume")
		get_viewport().set_input_as_handled()
