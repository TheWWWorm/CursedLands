class_name ArenaResultVolley
extends FlyingHP
## Native fire-bolt particles in a transparent HUD viewport. Presentation only:
## no combat casts, damage events, saved unit references or delayed health loss.
const PIXELS_PER_METRE := 64.0
var _container: SubViewportContainer
var _view: SubViewport
var _camera: Camera3D
var _fx: ParticleFx
var _events: Array[Dictionary] = []
var _flights: Array[Dictionary] = []
var _popups: Array[Dictionary] = []
var _tail := 0.0
var launches := 0

func _ready() -> void:
	super._ready()
	_container = SubViewportContainer.new()
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.stretch = true
	# Native additive sprites contain opaque black quads. Recover coverage
	# from their RGB so the HUD preserves the fire colour on bright snow too.
	var composite := ShaderMaterial.new()
	composite.shader = Shader.new()
	composite.shader.code = """shader_type canvas_item;
render_mode unshaded;
void fragment() {
	vec3 fire = texture(TEXTURE, UV).rgb;
	float coverage = clamp(max(fire.r, max(fire.g, fire.b)), 0.0, 1.0);
	COLOR = vec4(fire / max(coverage, 0.001), coverage);
}
"""
	_container.material = composite
	add_child(_container)
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.transparent_bg = true
	_view.gui_disable_input = true
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_container.add_child(_view)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.1; _camera.far = 80.0
	_view.add_child(_camera)
	_camera.current = true
	resized.connect(_fit)
	_fit()
	set_process(false)
	hide()

func _fit() -> void:
	if not is_instance_valid(_camera) or size.y < 1: return
	var center := Vector3(size.x * 0.5 / PIXELS_PER_METRE, 0, -size.y * 0.5 / PIXELS_PER_METRE)
	_camera.position = center + Vector3(0, 40, 0)
	_camera.look_at(center, Vector3(0, 0, -1))
	_camera.size = size.y / PIXELS_PER_METRE

func present(starts: PackedVector2Array, target: Vector2, damage: int, friendly_loss: bool, scale_factor: float, follow_target := Callable()) -> void:
	if damage <= 0: return
	if not is_instance_valid(_fx):
		_fx = ParticleFx.new()
		_view.add_child(_fx)
		_fx.set_process(false)
	var delay := 0.0
	for point in starts:
		_events.append({"left":delay, "start":point, "target":target, "scale":scale_factor, "follow":follow_target})
		delay += 0.065
	# Use the actual combat atlas, colours, sizing, drift and fade. Leave room
	# for the native up/right motion beside the standings at the screen edge.
	var glyph_scale := maxf(1.5, UiScale.fit(size))
	var at := target - Vector2(30, 12) * scale_factor
	at.x = minf(at.x, size.x - (124 + str(damage).length() * 4) * glyph_scale)
	at.y = maxf(at.y, 106 * glyph_scale)
	_popups.append({"n":damage, "party":friendly_loss, "age":0.0, "at":at})
	_tail = maxf(_tail, delay + 3.0)
	show(); _view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_process(true)
	queue_redraw()

func _draw() -> void:
	if _tex == null: return
	for popup in _popups:
		for glyph: Dictionary in readable_layout(popup.at, popup.n, 0, popup.party, roundi(float(popup.age) * 1000), size):
			draw_texture_rect_region(_tex, glyph.rect, glyph.source, glyph.colour)

func _process(delta: float) -> void:
	var dt := delta / maxf(Engine.time_scale, 0.001)
	for event in _events.duplicate():
		event.left -= dt
		if event.left > 0: continue
		var target: Vector2 = event.target
		if event.follow.is_valid(): target = event.follow.call()
		var count := _fx.missiles.size()
		_fx._missile("arrow", _particle_point(event.start), null, _particle_point(target), 0.36 * float(event.scale), Spells.parse("arrow"))
		if _fx.missiles.size() > count and event.follow.is_valid():
			_flights.append({"missile":_fx.missiles.back(), "follow":event.follow})
		launches += 1
		_events.erase(event)
	if is_instance_valid(_fx):
		# Native missiles travel in world units. At large HUD resolutions a
		# valid flight can take longer than the minimum three-second tail.
		if not _fx.missiles.is_empty(): _tail = maxf(_tail,0.5)
		for flight in _flights.duplicate():
			if not _fx.missiles.has(flight.missile): _flights.erase(flight)
			elif flight.follow.is_valid(): flight.missile.point = _particle_point(flight.follow.call())
		_fx._process(dt)
	for popup in _popups.duplicate():
		popup.age += dt
		if popup.age >= FlyingHP.LIFE: _popups.erase(popup)
	queue_redraw()
	_tail -= dt
	if _tail <= 0 and _events.is_empty() and _popups.is_empty(): clear()

func _particle_point(point: Vector2) -> Vector3:
	# Resolve pixels through the actual HUD projection. Assuming EI y follows
	# screen y mirrored every destination around the middle of the viewport.
	var hit: Vector3 = Plane(Vector3.UP, 1.0).intersects_ray(_camera.project_ray_origin(point), _camera.project_ray_normal(point))
	return ParticleFx.ei(hit)

func clear() -> void:
	_events.clear()
	_flights.clear()
	_popups.clear()
	if is_instance_valid(_fx): _fx.queue_free()
	_fx = null
	if is_instance_valid(_view): _view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	hide(); set_process(false); queue_redraw()
