class_name InterfaceBoard
extends TextureRect
## A signpost board shown on an 800×600 interface screen: the original builds a
## CI3DFigure ((model, texture, labels texture)), hides every part
## ((0)) but the named ones, turns it about the view
## x axis and places it (x, y, depth): view
## position ((x·0.0025 − 1)·0.48157462·d, (y·0.0025 − 0.75)·0.48157462·d, d)
## with view x right, y down, z forward — the interface camera
## (tan 0.48157462 per 400 px). Like the rest of the 800×600 interface the
## picture is stretched to the window (rendered 4:3, drawn over the full rect).
## Interface figures are not lit by the world (CI3DFigure::Draw): unshaded.
## Examples: Options "unmoco1" escMenu00 / escMenu00labels
## parts "options" + "optionslabel", angle π/2, (400, 480, 4.8); network
## connection screen "unmoco2" MainMenu00 / MainMenu00labels
## parts "but03" + "button03_multiplayer", angle π/2 · 1.2, (400, 350, 8).

const TAN := 0.48157462

var _vp: SubViewport
var _cam: Camera3D
var _fig: Node3D


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
	stretch_mode = TextureRect.STRETCH_SCALE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.size = Vector2i(800, 600)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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
	for mi: MeshInstance3D in _fig.find_children("*", "MeshInstance3D", true, false):
		var part := String(mi.get_parent().name)
		# Label parts ("*label", "but03"...) carry the labels texture.
		var is_label := part.ends_with("label") or (part.begins_with("but") and not part.begins_with("button"))
		mi.material_override = lab_mat if is_label else tex_mat
	# EISpace.vec maps EI (x, y, z) to Godot (x, z, −y): exactly the original's π/2
	# turn about the view x axis seen from a Godot camera (view y down / z
	# forward = Godot −y / −z). Any further angle turns about x as well.
	_fig.basis = Basis(Vector3.RIGHT, -(angle - PI * 0.5))
	place(at)
	_vp.add_child(_fig)


## (x, y, depth): moves the board (the screens' slide-).
func place(at: Vector3) -> void:
	if _fig == null:
		return
	var d := at.z
	_fig.position = Vector3((at.x * 0.0025 - 1.0) * TAN * d, -(at.y * 0.0025 - 0.75) * TAN * d, -d)


static func texture_name(s: String) -> String:
	return s.to_lower()


static func _unshaded(m: StandardMaterial3D) -> StandardMaterial3D:
	var u: StandardMaterial3D = m.duplicate()
	u.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return u


func _process(_dt: float) -> void:
	# Render at the window height (4:3), drawn stretched over the full rect.
	var h := maxi(60, int(size.y))
	var want := Vector2i(int(round(h * 4.0 / 3.0)), h)
	if _vp and _vp.size != want:
		_vp.size = want
