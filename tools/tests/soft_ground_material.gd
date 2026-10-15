extends Node
## Sector material copies keep the current terrain uniforms and shared
## textures, including shader edits and option changes after the first mark.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)
func _ready() -> void:
	var terrain := EITerrain.new()
	var soft := SoftGroundDeform.new(); soft.terrain=terrain
	var source := ShaderMaterial.new(); terrain._land_mat=source
	source.shader=Shader.new()
	source.shader.code="shader_type spatial; uniform float amount=0.25; uniform vec3 tint=vec3(1.0); uniform sampler2D atlas;"
	var texture := ImageTexture.create_from_image(Image.create(8,8,false,Image.FORMAT_RGBA8))
	source.set_shader_parameter("atlas",texture)
	source.set_shader_parameter("tint",Vector3(0.2,0.4,0.6))
	source.set_shader_parameter("amount",0.7)
	source.render_priority=3; source.next_pass=StandardMaterial3D.new()
	var first := soft._copy_material()
	check(first!=source and first.shader==source.shader,"independent material retains shared shader")
	check(first.render_priority==3 and first.next_pass==source.next_pass,"render ordering and next pass retained")
	check(first.get_shader_parameter("atlas")==texture,"texture identity retained without readback")
	check(first.get_shader_parameter("tint")==Vector3(0.2,0.4,0.6),"vector uniform retained")
	check(is_equal_approx(first.get_shader_parameter("amount"),0.7),"scalar uniform retained")
	source.set_shader_parameter("amount",0.9)
	var second := soft._copy_material()
	check(is_equal_approx(second.get_shader_parameter("amount"),0.9) and is_equal_approx(first.get_shader_parameter("amount"),0.7),"later sectors use current values without changing earlier materials")
	source.shader.code += " uniform float snowfall=0.5;"
	source.set_shader_parameter("snowfall",0.8)
	check(is_equal_approx(soft._copy_material().get_shader_parameter("snowfall"),0.8),"editing a shader refreshes its uniform names")
	source.shader=Shader.new();source.shader.code="shader_type spatial; uniform float wetness=0.2;"
	source.set_shader_parameter("wetness",0.6)
	check(is_equal_approx(soft._copy_material().get_shader_parameter("wetness"),0.6),"replacing a shader refreshes its uniform names")
	soft.free();terrain.free()
	print("SOFT_GROUND_MATERIAL checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
