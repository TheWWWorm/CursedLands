class_name EscSignpost
extends InterfaceBoard
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
const REG := [["SaveGame", "save"], ["LoadGame", "load"], ["ResumeGame", "return2game"],
	["ExitMM", "exit2mainmenu"], ["Options", "options"]]

var _post: Node3D
var _player: AnimationPlayer
var _boards := {}
var _board_meshes := {}
var _rects: Array[Rect2] = []


func _ready() -> void:
	# The game is paused under the Esc menu (single player): the signpost, its
	# SubViewport and AnimationPlayer keep running.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pad_panel")   # remake: gamepad snap targets (PadUI)
	visibility_changed.connect(func():
		if visible:
			_on_open())
	# the same CI3DFigure projection as the other interface
	# screens, X-axis turn PI/2, screen position (400,700), depth 4.8.
	_build("unmoco1", "escmenu00", "escmenu00labels", PackedStringArray(), PI * 0.5, Vector3(400, 700, 4.8))
	mouse_filter = Control.MOUSE_FILTER_STOP
	_post = _fig
	if _post == null:
		return
	var reg: Dictionary = EIRegFile.parse(GameData.menus.read("menus.reg")).get("EscMenu", {})
	for e: Array in REG:
		var r: Array = reg.get(e[0], [])
		_rects.append(Rect2(r[0], r[1], r[2] - r[0], r[3] - r[1]) if r.size() == 4 else Rect2())
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
	# This UI camera is positioned outside physics ticks, including while the
	# game is paused. Picking must use that same pose rather than an old
	# interpolated transform cached by the SubViewport.
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_frame()


## Native placement; animation keys move only the figure's root part.
func _frame() -> void:
	place(Vector3(400, 700, 4.8))


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


## first menus.reg [EscMenu] rectangle containing the point
## with half-open right/bottom edges, in the stretched 800x600 interface.
func board_at(p: Vector2) -> String:
	if size.x <= 0.0 or size.y <= 0.0:
		return ""
	var q := p * Vector2(800, 600) / size
	for i in _rects.size():
		if _rects[i].has_point(q):
			return REG[i][1]
	return ""


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


## Gamepad snap targets use the same native hit rectangles as the pointer.
func pad_targets() -> Array:
	var out: Array = []
	if size.x <= 0.0 or size.y <= 0.0:
		return out
	var to_ctrl := size / Vector2(800, 600)
	var xf := get_global_transform_with_canvas()
	for i in _rects.size():
		var r := _rects[i]
		if r.size != Vector2.ZERO:
			out.append({"rect": Rect2(xf * (r.position * to_ctrl), r.size * to_ctrl), "id": BOARDS[REG[i][1]]})
	if pad_extra.is_valid():
		out.append_array(pad_extra.call())
	return out
