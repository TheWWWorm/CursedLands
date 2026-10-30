class_name InterfaceBoard
extends TextureRect
## A signpost board shown on an 800×600 interface screen: the original builds a
## CI3DFigure ((model, texture, labels texture)), hides every part
## ((0)) but the named ones, turns it about the view
## x axis and places it (x, y, depth): view
## position ((x·0.0025 − 1)·0.48157462·d, (y·0.0025 − 0.75)·0.48157462·d, d)
## with view x right, y down, z forward — the interface camera
## (tan 0.48157462 per 400 px). Like the rest of the 800×600 interface the
## picture retains the authored 4:3 proportions in the fitted interface frame.
## Interface figures are not lit by the world (CI3DFigure::Draw): unshaded.
## Examples: Options "unmoco1" escMenu00 / escMenu00labels
## parts "options" + "optionslabel", angle π/2, (400, 480, 4.8); network
## connection screen "unmoco2" MainMenu00 / MainMenu00labels
## parts "but03" + "button03_multiplayer", angle π/2 · 1.2, (400, 350, 8).

const TAN := 0.48157462

var _vp: SubViewport
var _cam: Camera3D
var _fig: Node3D
var _shown_at := Vector3.INF   # a board position its bound viewport picture has rendered
var _reveal_serial := 0
var _canvas_slide := false
var _slide_y := 0.0


static func create(model: String, skin: String, labels: String, parts: PackedStringArray,
		angle: float, at: Vector3) -> InterfaceBoard:
	var b := InterfaceBoard.new()
	b._build(model, skin, labels, parts, angle, at)
	return b


func _build(model: String, skin: String, labels: String, parts: PackedStringArray,
		angle: float, at: Vector3) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.size = Vector2i(800, 600)
	# Options, load and network screens are constructed while hidden. Their
	# TextureRect visibility must control rendering of the separate 3D view.
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	texture = _vp.get_texture()
	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.fov = rad_to_deg(2.0 * atan(0.75 * TAN))
	_cam.near = 0.05
	_vp.add_child(_cam)
	if not GameData.is_open():
		return
	_fig = EIFigure.instantiate(model, texture_name(skin), Vector3(0.5, 0.5, 0.5), parts)
	if _fig == null:
		return
	var tex_mat := _unshaded(EIFigure.material_for(texture_name(skin)))
	var lab_mat := _unshaded(EIFigure.material_for(texture_name(labels)))
	var figure_parts: Dictionary = EIFigure.get_model(model).get("parts", {})
	for mi: MeshInstance3D in _fig.find_children("*", "MeshInstance3D", true, false):
		var part := String(mi.get_parent().name)
		mi.material_override = lab_mat if is_label_part(part, figure_parts.get(part, {})) else tex_mat
	MenuCaptions.apply(_fig, model)
	if model == "unmoco2":
		MenuMultiplayerBoard.install(_fig, false)
	# EISpace.vec maps EI (x, y, z) to Godot (x, z, −y): exactly the original's π/2
	# turn about the view x axis seen from a Godot camera (view y down / z
	# forward = Godot −y / −z). Any further angle turns about x as well.
	_fig.basis = Basis(Vector3.RIGHT, -(angle - PI * 0.5))
	place(at)
	_vp.add_child(_fig)


## Parts of texture group 2 carry the labels texture, as in the original:
## the captions ("*label", "but03"...) and also the Esc signpost's foot
## (unmoco1 "coloumndetls"), whose stone block is drawn on the labels sheet.
## The name rule remains for parts without figure data.
static func is_label_part(part: String, figure: Dictionary) -> bool:
	if figure.has("texture_group"):
		return int(figure.texture_group) == 2
	return part.ends_with("label") or (part.begins_with("but") and not part.begins_with("button"))


## (x, y, depth): moves the board (the screens' slide-).
func place(at: Vector3) -> void:
	if _fig == null:
		return
	var d := at.z
	_fig.position = Vector3((at.x * 0.0025 - 1.0) * TAN * d, -(at.y * 0.0025 - 0.75) * TAN * d, -d)


## Translation at a fixed depth has exactly the same screen-space projection.
## Keep the viewport's picture at rest and move its canvas instead: an old
## texture is then safe even when the rendering thread is several frames late.
func slide(at: Vector3, offset_y: float) -> void:
	_canvas_slide = true
	_slide_y = offset_y
	place(at)
	_layout()


static func texture_name(s: String) -> String:
	return s.to_lower()


static func _unshaded(m: StandardMaterial3D) -> StandardMaterial3D:
	var u: StandardMaterial3D = m.duplicate()
	u.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return u


func _notification(what: int) -> void:
	if what != NOTIFICATION_VISIBILITY_CHANGED or _fig == null or _owns_reveal():
		return
	_reveal_serial += 1
	if not is_visible_in_tree():
		# Unbind the last picture rather than relying on alpha alone: ancestor
		# visibility notifications (a screen hidden and shown again within one
		# frame) also arrive here and must not expose it with a stale pose.
		texture = null
		self_modulate.a = 1.0
		_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	elif _canvas_slide or DisplayServer.get_name() == "headless" or _fig.position == _shown_at:
		texture = _vp.get_texture()
	else:
		_reveal()


## The Esc signpost binds its own picture after its opening clip renders.
func _owns_reveal() -> bool:
	return false


## Reopened elsewhere (a screen's slide starts below): the viewport still holds
## the picture of the previous opening on the first visible frame. Keep the
## board unbound until its new position has rendered, through two draw
## completions as the separate render thread may report the earlier draw first.
func _reveal() -> void:
	var serial := _reveal_serial
	texture = null
	# An empty TextureRect is not drawn; render the hidden board explicitly.
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var at := _fig.position
	for i in 2:
		await RenderingServer.frame_post_draw
		if serial != _reveal_serial or not is_visible_in_tree():
			return
	# The slide moves the board every frame; the picture now holds `at` or a
	# later pose, never the previous opening.
	_shown_at = at
	texture = _vp.get_texture()
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE


func _process(_dt: float) -> void:
	if not is_visible_in_tree():
		return
	if texture != null and _fig != null and not _owns_reveal():
		_shown_at = _fig.position
	_layout()
	var h := maxi(60, int(Interface800.fit_rect(Rect2(Vector2.ZERO, size)).size.y))
	var want := Vector2i(int(round(h * 4.0 / 3.0)), h)
	if _vp and _vp.size != want:
		_vp.size = want


func _layout() -> void:
	# Normal interface boards follow the parent's safe-area and touch-zoom
	# mapping. The standalone Esc signpost fills its parent but fits its 4:3
	# texture inside it; its pointer and gamepad targets use the same frame.
	var screen := get_parent() as Interface800
	if screen:
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		var rect := screen.r8(Rect2(0, 0, 800, 600))
		position = rect.position
		size = rect.size
		position.y += _slide_y * rect.size.y / 600.0
