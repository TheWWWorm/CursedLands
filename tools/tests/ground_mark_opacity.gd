extends Node
## Renderer colours/uniforms are float32. A double-precision alpha must not
## cause unchanged marks to upload their same visible opacity every tick.
var checks := 0
var failures := 0
class CountingMaterial extends ShaderMaterial:
	var writes := 0
	@warning_ignore("native_method_override")
	func set_shader_parameter(param: StringName, value: Variant) -> void:
		writes += 1
		super.set_shader_parameter(param, value)
class Recorder extends GroundMarks:
	var placements := []
	func _place(m: Mark) -> void:
		placements.append([m.x,m.y,m.a,m.b,m.angle,m.life,m.decal.modulate])
class Legacy extends Recorder:
	# Unchanged _update from 1bc39a05; independent fade/placement oracle.
	func _update(m: Mark) -> int:
		var moved := false
		if not m.foot:
			m.grow_left -= 1
			if m.grow_left < 0:
				m.grow = 0.0
			m.angle += m.spin
			moved = m.grow != 0.0 or m.spin != 0.0
		m.life -= 1
		m.a += m.grow
		m.b += m.grow
		var f := float(m.fade - m.life) / float(m.fade)
		var alpha := _decal_alpha((1.0 - maxf(f, 0.0)) * m.alpha0)
		if moved:
			_place(m)
		if m.decal.modulate.a != alpha:
			m.decal.modulate.a = alpha
			if m.projection: m.projection.material_override.set_shader_parameter("opacity",alpha)
		return m.life

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 12: printerr("FAIL ", label)

func make_mark(values: Dictionary, projected := true) -> GroundMarks.Mark:
	var m := GroundMarks.Mark.new()
	for key in values: m.set(key, values[key])
	m.decal = Decal.new()
	var alpha := GroundMarks._decal_alpha(m.alpha0 * minf(1.0, float(m.life) / float(m.fade)))
	m.decal.modulate = Color(.2, .4, .6, alpha)
	if projected:
		m.projection = MeshInstance3D.new()
		var material := CountingMaterial.new()
		var shader := Shader.new()
		shader.code = "shader_type spatial; uniform float opacity=1.0; void fragment(){ALBEDO=vec3(1.0);ALPHA=opacity;}"
		material.shader = shader
		material.set_shader_parameter(&"opacity", alpha)
		material.writes = 0
		m.projection.material_override = material
	return m

func state(m: GroundMarks.Mark) -> Array:
	var opacity := PackedFloat32Array([m.projection.material_override.get_shader_parameter(&"opacity")])[0] if m.projection else -1.0
	return [m.life,m.grow_left,m.grow,m.a,m.b,m.angle,m.decal.modulate,opacity]

func dispose(m: GroundMarks.Mark) -> void:
	m.decal.free()
	if m.projection: m.projection.free()

func _ready() -> void:
	var current := Recorder.new()
	var old := Legacy.new()
	for alpha: float in [.01,.2,.5,.8,.99]:
		var a := make_mark({"foot":true,"life":1000,"fade":100,"alpha0":alpha})
		var b := make_mark({"foot":true,"life":1000,"fade":100,"alpha0":alpha})
		for frame in 100:
			current._update(a); old._update(b)
			check(state(a) == state(b), "opaque footprint state alpha=%s frame=%d" % [alpha,frame])
		check(a.projection.material_override.writes == 0, "unchanged float32 opacity is never uploaded again")
		check(b.projection.material_override.writes == 100, "negative control reproduces redundant old uploads")
		dispose(a); dispose(b)
	var rng := RandomNumberGenerator.new(); rng.seed = 20261025
	for sample in 128:
		var values := {"foot":sample%3==0,"life":rng.randi_range(1,100),"fade":rng.randi_range(1,100),
			"alpha0":rng.randf_range(-.1,1.1),"a":.2,"b":.3,"angle":.5,
			"grow":rng.randf_range(-.001,.01),"grow_left":rng.randi_range(0,30),"spin":.02 if sample%2==0 else 0.0}
		if sample%7==0: values.life=2147483647; values.fade=2147483647
		var a := make_mark(values, sample%5!=0)
		var b := make_mark(values, sample%5!=0)
		for frame in 40:
			if frame%13==0:
				var colour := Color(rng.randf(),rng.randf(),rng.randf(),rng.randf())
				a.decal.modulate=colour; b.decal.modulate=colour
			current.placements.clear(); old.placements.clear()
			check(current._update(a) == old._update(b), "same expiry result")
			check(state(a) == state(b), "same mark fields and renderer opacity")
			check(current.placements == old.placements, "same ordered growth/rotation placement")
		dispose(a); dispose(b)
	current.free(); old.free()
	print("GROUND_MARK_OPACITY checks=",checks," failures=",failures)
	get_tree().quit(int(failures>0))
