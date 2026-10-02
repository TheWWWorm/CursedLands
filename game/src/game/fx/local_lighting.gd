class_name LocalLighting
extends Node
## Remake-only light response from existing flames, spell lights and exposed
## lava. No events or gameplay state: one manager per local Game. Torches and
## spells keep their original light records, which are restored verbatim when
## gfx_firelight is off. Lava uses a small reusable pool, independently gated
## by gfx_lava_light, and follows the current SetWaterLevel surface.

const SCAN := 0.25
const SHADOW_LIMIT := 4
const LAVA_LIMIT := 6
const LAVA_SHADOW_LIMIT := 2
const LAVA_SCAN_RADIUS := 46.0
const LAVA_SPACING := 7.0
const LAVA_RADIUS := 6.0
const FIRE_COLOR := Color(1.0, 0.70, 0.42)
const FIRE_ENERGY := 1.7
# Let the flame and the light landing on nearby surfaces carry the effect.
# A full-strength coloured billboard turns the fire into a yellow fog ball.
const FIRE_HALO := 0.24
const LAVA_COLOR := Color(1.0, 0.25, 0.055)
const ORIGINAL_PROPERTIES := [&"light_color", &"light_energy", &"light_specular", &"shadow_enabled",
	&"light_cull_mask", &"shadow_caster_mask", &"distance_fade_enabled", &"distance_fade_begin",
	&"distance_fade_shadow", &"distance_fade_length", &"shadow_bias", &"shadow_normal_bias", &"shadow_blur"]

var game: Game
var _world: GameWorld
var _t := 0.0
var _time := 0.0
var _fire_on := false
var _lava_on := false
var _lava: Array[Dictionary] = []


func _init(g: Game) -> void:
	game = g
	name = "LocalLighting"


func _ready() -> void:
	GameData.options_changed.connect(apply_options)
	apply_options()


func _exit_tree() -> void:
	_restore_particles()


## Called at light creation as well, so even a short spell flash enters the
## right shader path before its first rendered frame. The snapshot precedes
## every enhancement and is never replaced by an already enhanced state.
static func prepare_particle(d: Dictionary) -> void:
	if String(d.get("kind", "")) not in ["fire", "spell"]:
		return
	var l: OmniLight3D = d.light
	var original := {}
	for property: StringName in ORIGINAL_PROPERTIES:
		original[property] = l.get(property)
	d["original"] = original
	# Only stationary fire sources move. Spell lights keep following their
	# current scripted position even when this option is switched off.
	if d.kind == "fire":
		d["original_position"] = l.position
	d["enhanced"] = false
	var halo := d.get("halo") as ShaderMaterial
	if halo:
		d["halo_color"] = halo.get_shader_parameter("col")
		var strength = halo.get_shader_parameter("strength")
		d["halo_strength"] = float(strength) if strength != null else 0.55
	var p: Vector3 = d.pos
	d["phase"] = fposmod(p.x * 0.713 + p.y * 1.117 + p.z * 0.379, TAU)
	apply_particle(d, Gfx.on("gfx_firelight"))


static func apply_particle(d: Dictionary, enabled: bool) -> void:
	if not d.has("original") or not is_instance_valid(d.get("light")):
		return
	if bool(d.get("enhanced", false)) == enabled:
		return
	var l: OmniLight3D = d.light
	d.enhanced = enabled
	if not enabled:
		for property: StringName in d.original:
			# SpellFx owns a live fade even while gameplay is paused; an
			# option change must not reset it to its creation-time energy.
			if property == &"light_energy" and d.get("external_energy", false):
				continue
			l.set(property, d.original[property])
		if d.has("original_position"):
			l.position = d.original_position
		if d.has("halo_color"):
			d.halo.set_shader_parameter("col", d.halo_color)
			d.halo.set_shader_parameter("strength", d.halo_strength)
		return
	l.light_specular = Gfx.LOCAL_SPECULAR
	_light_quality(l)
	if d.kind == "fire":
		l.light_color = FIRE_COLOR
		l.light_energy = float(d.energy) * FIRE_ENERGY
		# The original offset is near the bowl rim. Emit from within the
		# existing flame so that rim does not cast an oversized dark polygon.
		l.position = d.original_position + Vector3.UP * minf(l.omni_range * 0.1, 0.45)
		# Filter the point-source shadow. Changing light_size at runtime
		# breaks Godot 4.7's soft-shadow pairing counts when this is toggled.
		l.shadow_blur = 2.5
		if d.has("halo_color"):
			d.halo.set_shader_parameter("col", Vector3(FIRE_COLOR.r, FIRE_COLOR.g, FIRE_COLOR.b))
			d.halo.set_shader_parameter("strength", float(d.halo_strength) * FIRE_HALO)
	elif d.get("external_energy", false) and d.has("halo_strength"):
		# Apply immediately: a paused spell cannot refresh its halo until
		# the game resumes, but the settings screen can still toggle it.
		d.halo.set_shader_parameter("strength", float(d.halo_strength)
			* clampf(l.light_energy / maxf(float(d.energy), 0.001), 0.0, 1.0))


static func _light_quality(l: OmniLight3D) -> void:
	l.light_cull_mask &= ~GameUnit.OFFSCREEN_LAYER
	l.shadow_caster_mask &= ~GameUnit.OFFSCREEN_LAYER
	l.shadow_bias = 0.025
	l.shadow_normal_bias = 0.35
	l.shadow_blur = 1.25
	l.distance_fade_enabled = true
	l.distance_fade_begin = 65.0
	l.distance_fade_shadow = 55.0
	l.distance_fade_length = 20.0


func apply_options() -> void:
	_fire_on = Gfx.on("gfx_firelight")
	_lava_on = Gfx.on("gfx_lava_light")
	if is_instance_valid(_world):
		var fx := _world.get_node_or_null("ParticleFx") as ParticleFx
		for d: Dictionary in _light_records(fx):
			apply_particle(d, _fire_on)
	if not _lava_on:
		_clear_lava()
	_t = 0.0


func _restore_particles() -> void:
	if not is_instance_valid(_world):
		return
	var fx := _world.get_node_or_null("ParticleFx") as ParticleFx
	for d: Dictionary in _light_records(fx):
		apply_particle(d, false)


## Non-missile spell flashes retain their own lifetime/energy controller in
## SpellFx. Include their existing lights in the same quality/shadow budget
## without transferring ownership or creating a second light at the target.
func _light_records(fx: ParticleFx) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if fx:
		records.assign(fx.lights)
	if is_instance_valid(_world) and is_inside_tree():
		for light: Node in get_tree().get_nodes_in_group(&"ei_local_spell"):
			if _world.is_ancestor_of(light):
				records.append(light.get_meta(&"ei_local_light"))
	return records


func _clear_lava() -> void:
	for d: Dictionary in _lava:
		if is_instance_valid(d.light):
			d.light.visible = false
			d.light.queue_free()
	_lava.clear()


func _process(dt: float) -> void:
	var current: GameWorld = game.world if is_instance_valid(game) else null
	if not is_instance_valid(_world) or _world != current:
		_restore_particles()
		_clear_lava()
		_world = current
		_t = 0.0
	if not is_instance_valid(_world):
		return
	_time += dt
	var fx := _world.get_node_or_null("ParticleFx") as ParticleFx
	for d: Dictionary in _light_records(fx):
		apply_particle(d, _fire_on)
		if _fire_on and d.get("kind", "") == "fire" and is_instance_valid(d.light):
			# Independent, gentle flame flutter. This does not consume the
			# original particle RNG or change any effect's timing.
			var phase := float(d.phase)
			var flutter := 1.0 + 0.045 * sin(_time * 8.3 + phase) \
				+ 0.025 * sin(_time * 13.7 + phase * 2.3) + 0.02 * sin(_time * 3.1 + phase)
			d.light.light_energy = float(d.energy) * FIRE_ENERGY * flutter
			if d.has("halo_strength"):
				d.halo.set_shader_parameter("strength", float(d.halo_strength) * FIRE_HALO * flutter)
		elif _fire_on and d.get("kind", "") == "spell" and int(d.until) >= 0 and is_instance_valid(d.light):
			# A small end fade follows the existing lifetime without changing
			# expiry ticks, scripted movement or the original/off path.
			var fade_ticks := minf(6.0, maxf(1.0, float(d.duration_ticks) * 0.25))
			var left := float(int(d.until) - fx.tick) - fx.acc / ParticleFx.TICK
			var fade := smoothstep(0.0, fade_ticks, left)
			d.light.light_energy = float(d.energy) * fade
			if d.has("halo_strength"):
				d.halo.set_shader_parameter("strength", float(d.halo_strength) * fade)
	_t -= dt
	if _t <= 0.0:
		_t = SCAN
		var camera := get_viewport().get_camera_3d()
		var focus := game.rig.global_position if is_instance_valid(game.rig) else Vector3.ZERO
		if camera:
			if _lava_on and _world.terrain:
				_scan_lava(_world.terrain, camera, focus)
			_assign_shadows(fx, camera, focus)
		else:
			_disable_shadows(fx)
	for d: Dictionary in _lava:
		var l: OmniLight3D = d.light
		var target := 0.58 if d.active else 0.0
		d.energy = move_toward(float(d.energy), target, dt * 2.0)
		l.light_energy = float(d.energy) * (1.0 + 0.035 * sin(_time * 2.1 + float(d.cell) * 0.37))
		l.visible = l.light_energy > 0.001


static func _in_view(camera: Camera3D, p: Vector3, radius: float) -> bool:
	for plane: Plane in camera.get_frustum():
		if plane.distance_to(p) > radius:
			return false
	return true


static func _exposed_lava(t: EITerrain, x: int, y: int, width: int, height: int) -> bool:
	if x < 0 or y < 0 or x >= width or y >= height:
		return false
	var i := y * width + x
	return i < t.liquid_ground.size() and i < t.water.size() and t.liquid_ground[i] == EITerrain.LAVA \
		and is_finite(t.water[i]) and t.water[i] > t.height_at(x + 0.5, y + 0.5) + 0.04


func _scan_lava(t: EITerrain, camera: Camera3D, focus: Vector3) -> void:
	var width := t.sectors_x * EITerrain.SECTOR
	var height := t.sectors_y * EITerrain.SECTOR
	var cx := focus.x
	var cy := -focus.z
	var x0 := maxi(0, floori((cx - LAVA_SCAN_RADIUS) * 0.5) * 2)
	var y0 := maxi(0, floori((cy - LAVA_SCAN_RADIUS) * 0.5) * 2)
	var x1 := mini(width, ceili(cx + LAVA_SCAN_RADIUS))
	var y1 := mini(height, ceili(cy + LAVA_SCAN_RADIUS))
	var previous := {}
	for d: Dictionary in _lava:
		if d.active:
			previous[int(d.cell)] = true
	var candidates: Array[Dictionary] = []
	# Liquid atlas tiles cover 2 x 2 cells. The bounded region is about 2200
	# samples, independent of zone size; no full-map light or bank list.
	for y in range(y0, y1, 2):
		for x in range(x0, x1, 2):
			if not _exposed_lava(t, x, y, width, height):
				continue
			var cell := y * width + x
			var p := Vector3(x + 0.5, t.water[cell] + 0.5, -(y + 0.5))
			if p.distance_squared_to(focus) > LAVA_SCAN_RADIUS * LAVA_SCAN_RADIUS \
					or p.distance_squared_to(camera.global_position) > 85.0 * 85.0 \
					or not _in_view(camera, p, LAVA_RADIUS):
				continue
			if _exposed_lava(t, x - 2, y, width, height) and _exposed_lava(t, x + 2, y, width, height) \
					and _exposed_lava(t, x, y - 2, width, height) and _exposed_lava(t, x, y + 2, width, height):
				continue
			var score := p.distance_squared_to(focus)
			if previous.has(cell):
				score *= 0.8   # retain a bank while panning near an equal candidate
			candidates.append({"cell": cell, "pos": p, "score": score})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score < b.score)
	var chosen: Array[Dictionary] = []
	for c: Dictionary in candidates:
		var nearby := false
		for old: Dictionary in chosen:
			if c.pos.distance_squared_to(old.pos) < LAVA_SPACING * LAVA_SPACING:
				nearby = true
				break
		if nearby:
			continue
		chosen.append(c)
		if chosen.size() == LAVA_LIMIT:
			break
	_sync_lava(chosen)


func _new_lava() -> Dictionary:
	var l := OmniLight3D.new()
	l.name = "LavaLight"
	l.light_color = LAVA_COLOR
	l.light_energy = 0.0
	l.light_specular = Gfx.LOCAL_SPECULAR
	l.light_volumetric_fog_energy = 0.0
	l.omni_range = LAVA_RADIUS
	l.omni_attenuation = 0.0
	l.visible = false
	_light_quality(l)
	add_child(l)
	var d := {"light": l, "cell": -1, "active": false, "energy": 0.0}
	_lava.append(d)
	return d


func _sync_lava(chosen: Array[Dictionary]) -> void:
	var by_cell := {}
	var pending: Array[Dictionary] = []
	for d: Dictionary in _lava:
		d.active = false
		by_cell[int(d.cell)] = d
	for c: Dictionary in chosen:
		if by_cell.has(int(c.cell)):
			var d: Dictionary = by_cell[int(c.cell)]
			d.active = true
			d.light.global_position = c.pos
		else:
			pending.append(c)
	for c: Dictionary in pending:
		var slot := {}
		for d: Dictionary in _lava:
			if not d.active:
				slot = d
				break
		if slot.is_empty():
			slot = _new_lava()
		slot.cell = c.cell
		slot.active = true
		slot.energy = 0.0
		slot.light.light_energy = 0.0
		Gfx.set_local_shadow(slot.light, false)
		slot.light.global_position = c.pos
	for d: Dictionary in _lava:
		if not d.active:
			Gfx.set_local_shadow(d.light, false)


func _disable_shadows(fx: ParticleFx) -> void:
	for d: Dictionary in _light_records(fx):
		if d.get("enhanced", false) and is_instance_valid(d.light):
			Gfx.set_local_shadow(d.light, false)
	for d: Dictionary in _lava:
		Gfx.set_local_shadow(d.light, false)


func _assign_shadows(fx: ParticleFx, camera: Camera3D, focus: Vector3) -> void:
	var fire: Array[Dictionary] = []
	var lava: Array[Dictionary] = []
	var records := _light_records(fx)
	if _fire_on:
		for d: Dictionary in records:
			if not d.get("enhanced", false) or not is_instance_valid(d.light):
				continue
			var l: OmniLight3D = d.light
			var p := l.global_position
			var score := p.distance_squared_to(focus) + p.distance_squared_to(camera.global_position) * 0.15
			if p.distance_squared_to(camera.global_position) < 65.0 * 65.0 and _in_view(camera, p, l.omni_range):
				fire.append({"light": l, "score": score * (0.8 if l.shadow_enabled else 1.0)})
	for d: Dictionary in _lava:
		if d.active and d.light.global_position.distance_squared_to(camera.global_position) < 65.0 * 65.0:
			lava.append({"light": d.light, "score": d.light.global_position.distance_squared_to(focus)})
	fire.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score < b.score)
	lava.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score < b.score)
	var selected := {}
	var lava_count := mini(LAVA_SHADOW_LIMIT, lava.size())
	for i in lava_count:
		selected[lava[i].light] = true
	for i in mini(SHADOW_LIMIT - lava_count, fire.size()):
		selected[fire[i].light] = true
	for d: Dictionary in records:
		if d.get("enhanced", false) and is_instance_valid(d.light):
			Gfx.set_local_shadow(d.light, selected.has(d.light))
	for d: Dictionary in _lava:
		Gfx.set_local_shadow(d.light, selected.has(d.light))
