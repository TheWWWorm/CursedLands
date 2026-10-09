class_name CameraDepthOfField
extends Node
## Optional R1 camera policy over Godot's far-only blur. Focus is the rig's
## actual look-at target, not R1's median rendered-depth samples. No readback
## or custom screen compositor: Godot keeps Canvas UI outside the 3D pass.
const STRENGTH := 0.2
const FOCUS_SECONDS := 0.3
const MIN_FOCUS := 2.0
const MAX_FOCUS := 600.0
var rig: CameraRig
var _camera: Camera3D
var _original: CameraAttributes
var _attributes: CameraAttributesPractical
var _focus := 0.0
var _last_eye := Vector3.ZERO
var _last_forward := Vector3.ZERO
var _yielded: WeakRef


static func supported(method := RenderingServer.get_current_rendering_method()) -> bool:
	return OS.has_feature("ei_far_dof_guard") and method in ["forward_plus", "mobile"]


## R1 depth_of_field_pitch_factor: exact smooth fade from 25° to 50°.
static func pitch_factor(depression: float) -> float:
	var t := clampf((50.0 - depression) / 25.0, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func lens(depression: float, focus: float, height: float) -> Dictionary:
	focus = clampf(focus, MIN_FOCUS, MAX_FOCUS)
	var factor := pitch_factor(depression)
	var radius := 0.012 * STRENGTH * height * factor * clampf(40.0 / focus, 0.5, 1.0)
	var divisor := 3.0 if height > 1440.0 else 2.0
	var begin := focus * (1.0 + 0.6 / (0.4 + STRENGTH))
	# Godot uses a 64px base radius. A positive transition works on both
	# Forward+ and Mobile; the engine supplies its own smooth blur kernel.
	return {"active": radius / divisor >= 0.25, "amount": radius / 64.0,
		"begin": begin, "transition": begin * 2.0}


func _init(owner_rig: CameraRig = null) -> void:
	rig = owner_rig
	process_priority = 100 # after the rig and third-person camera updates
	process_mode = Node.PROCESS_MODE_ALWAYS


func clear() -> void:
	if is_instance_valid(_camera) and _attributes and _camera.attributes == _attributes:
		_camera.attributes = _original
	_attributes = null
	_original = null
	_camera = null
	_focus = 0.0


func _process(dt: float) -> void:
	var game := rig.get_parent() as Game if is_instance_valid(rig) else null
	if game == null or not is_instance_valid(game.world) or not is_instance_valid(rig.camera) \
			or not rig.camera.is_current() or (game.session and game.session.movie_active()):
		clear()
		return
	update(rig.camera, rig.presentation_focus(), dt, Gfx.on("gfx_depth_of_field"))


func update(camera: Camera3D, target: Vector3, dt: float, enabled: bool) -> void:
	if not enabled:
		_yielded = null
		clear()
		return
	if not supported() or camera.get_viewport().transparent_bg or not target.is_finite():
		clear()
		return
	if _camera != camera:
		clear()
	if _yielded and _yielded.get_ref() == camera:
		return
	# Never replace another owner or a physical camera's exposure/FOV policy.
	if _attributes and camera.attributes != _attributes:
		_yielded = weakref(camera)
		clear()
		return
	var inherited := camera.attributes if camera.attributes else camera.get_world_3d().camera_attributes
	if inherited != null and not inherited is CameraAttributesPractical:
		clear()
		return
	var forward := -camera.global_basis.z.normalized()
	var depression := rad_to_deg(asin(clampf(-forward.y, -1.0, 1.0)))
	var wanted := clampf((target - camera.global_position).dot(forward), MIN_FOCUS, MAX_FOCUS)
	var cut := _focus <= 0.0 or camera.global_position.distance_to(_last_eye) > maxf(8.0, _focus * 0.5) \
		or forward.dot(_last_forward) < 0.5
	_focus = wanted if cut else exp(lerpf(log(_focus), log(wanted), 1.0 - exp(-maxf(dt, 0.0) / FOCUS_SECONDS)))
	var vp := camera.get_viewport()
	var height := vp.get_visible_rect().size.y * vp.scaling_3d_scale
	var parameters := lens(depression, _focus, height)
	if not parameters.active:
		clear() # steep tactical view has no blur resource or focus history
		return
	if _attributes == null:
		_camera = camera
		_original = camera.attributes
		_attributes = inherited.duplicate() as CameraAttributesPractical if inherited else CameraAttributesPractical.new()
		camera.attributes = _attributes
	_attributes.dof_blur_near_enabled = false
	_attributes.dof_blur_far_enabled = true
	_attributes.dof_blur_far_distance = parameters.begin
	_attributes.dof_blur_far_transition = parameters.transition
	_attributes.dof_blur_amount = parameters.amount
	_last_eye = camera.global_position
	_last_forward = forward


func _exit_tree() -> void:
	clear()
