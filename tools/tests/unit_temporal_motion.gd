extends Node
## Toggle real viewport reconstruction on already-created world materials.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _ready() -> void:
	GameData.options.merge({"q_aa":0,"rtx_upscaling":0,"fsr_upscaling":0,"gfx_volumetric":0},true)
	Gfx.ensure_globals()
	var root := get_tree().root
	root.scaling_3d_scale = 1.0
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	Gfx.apply_quality(root)
	var material := EIUnitModel.LitMaterial.new()
	material.set_shader_parameter("unit_emission", Vector3(.1,.2,.3))
	material.set_shader_parameter("wound_enabled", true)
	var original := material.shader
	var fade := CameraFade.dither_shader(original)
	var preview := EIUnitModel.PreviewMaterial.new()
	var wisp := EIUnitModel._material(false,true) as ShaderMaterial
	var preview_code := preview.shader.code
	var wisp_code := wisp.shader.code
	var native_code := original.code
	check(native_code.contains("alpha_to_coverage"),"native shader retains MSAA coverage")
	for temporal in [true,false,true,false]:
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if temporal else Viewport.SCALING_3D_MODE_BILINEAR
		Gfx.apply_quality(root)
		var code := material.shader.code
		check(code.contains("alpha_to_coverage") != temporal,"world cutout enters the opaque motion pass")
		check(code.contains("ALPHA_ANTIALIASING_EDGE") != temporal,"coverage edge disabled only for temporal view")
		check(code.contains("ALPHA_TEXTURE_COORDINATE") != temporal,"coverage coordinate disabled only for temporal view")
		check(code.contains("ALPHA_SCISSOR_THRESHOLD = 0.5;"),"authored cutout retained")
		check(code.contains("ALPHA = t.a * ei_material_diffuse.a;"),"texture/material alpha retained")
		check(code.contains("if (unit_stealth > 0.0)"),"stealth dithering retained")
		check(material.shader == original,"live material and shader identities retained")
		check(material.get_shader_parameter("unit_emission") == Vector3(.1,.2,.3),"material lighting retained")
		check(material.get_shader_parameter("wound_enabled") == true,"wound state retained")
		check(fade.code == CameraFade._dither_code(code),"existing camera-fade shader follows the switch")
		check(preview.shader.code == preview_code,"MSAA interface previews unchanged")
		check(wisp.shader.code == wisp_code and not wisp_code.contains("ALPHA_SCISSOR_THRESHOLD"),"translucent wisps unchanged")
		var fresh := Shader.new();fresh.code = code
		check(not fresh.get_shader_uniform_list().is_empty(),"selected shader parses")
	check(original.code == native_code,"native shader restored exactly")
	CameraFade._derived.clear();CameraFade._shaders.clear();TexUpscale.shutdown()
	print("UNIT_TEMPORAL_MOTION checks=",checks," failures=",failures)
	get_tree().quit(int(failures != 0))
