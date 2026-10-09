extends Node
## Historical diagnostic: compare sRGB wound sampling with legacy baked albedo.
## No gameplay/material ownership changes. Layer composition stays byte-native.
## Production raw-UNORM acceptance is tools/tests/wound_gpu_contract.gd.

const CONVERSIONS := """
uniform sampler2D wound_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
vec3 wound_encoded(vec3 c) {
	if (OUTPUT_IS_SRGB) { return c; }
	return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055,
		step(vec3(0.0031308), c));
}
vec3 wound_linear(vec3 c) {
	if (OUTPUT_IS_SRGB) { return c; }
	return mix(c / 12.92, pow(max((c + 0.055) / 1.055, vec3(0.0)), vec3(2.4)),
		step(vec3(0.04045), c));
}
"""
const BLEND := """
	vec4 w = ei_unit_tex(wound_tex, UV);
	float a = w.a + t.a * (1.0 - w.a);
	vec3 b = BASE_COLOUR;
	vec3 c = WOUND_COLOUR;
	vec3 blended = (b * t.a * (1.0 - w.a) + c * w.a) / max(a, 1e-8);
	t = vec4(RESULT_COLOUR, a);
"""

var checks := 0
var failures := 0
var rows := []
var timings := []
var view: SubViewport
var draw: MeshInstance3D
var camera: Camera3D
var programs := {}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func frames(count: int) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

func layers(mask: String, lv: PackedByteArray, human: bool) -> Array:
	var out := []
	var codes: Array = UnitWounds.HUMAN_CODES if human else UnitWounds.OTHER_CODES
	for i in 6:
		if lv[i] == 0: continue
		var name := "%s%sw%d" % [mask,codes[i],lv[i]]
		var data := UnitWounds._layer_bytes(name)
		out.append([name,UnitWounds._decode(data) if not data.is_empty() else null,data])
	return out

func overlay(inputs: Array) -> Image:
	# Deliberately mirrors the current layer stage as an experimental oracle.
	# Production _build below independently verifies its composed result.
	var pixels := PackedByteArray(); var size := Vector2i.ZERO
	for row: Array in inputs:
		var img := row[1] as Image
		if img == null: continue
		if pixels.is_empty(): size = img.get_size(); pixels.resize(size.x * size.y * 4)
		elif img.get_size() != size: continue
		var bytes: PackedByteArray = row[2]
		var pnt3 := bytes.size() >= EIMmp.DATA_OFFSET and bytes.decode_u32(16) == 0x33544e50
		pixels = UnitWounds._blend_native(pixels,bytes.slice(EIMmp.DATA_OFFSET) if pnt3 else img.get_data(),pnt3,pnt3)
	if pixels.is_empty(): return null
	return Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBA8,UnitWounds._argb4444(pixels))

func baked(base: Image, inputs: Array) -> Image:
	var job := {"src":base,"layers":inputs,"out":null,"decoded":{}}
	UnitWounds._build(job)
	return job.out

func material(base: Texture2D, wound: Texture2D, mode: String) -> ShaderMaterial:
	if not programs.has(mode):
		var source := EIUnitModel.PREVIEW_SHADER.replace("cull_back, diffuse_lambert, specular_disabled, alpha_to_coverage","unshaded, cull_disabled")
		# Keep this rejected candidate reproducible after shipping the separate
		# raw-UNORM sampler; do not blend two wound stages or redeclare its sampler.
		var constants: Dictionary = load("res://src/ei/unit_model.gd").get_script_constant_map()
		if constants.has("WOUND_FETCH"):
			source = source.replace(constants.WOUND_FETCH, "").replace("\tif (wound_enabled) { t = ei_unit_wound(t, ei_unit_tex(wound_tex, UV)); }\n", "")
		if mode != "baked":
			var encoded := mode in ["encoded","sized"]
			var blend := BLEND.replace("BASE_COLOUR","wound_encoded(t.rgb)" if encoded else "t.rgb")
			blend = blend.replace("WOUND_COLOUR","wound_encoded(w.rgb)" if encoded else "w.rgb")
			blend = blend.replace("RESULT_COLOUR","wound_linear(blended)" if encoded else "blended")
			source = source.replace("void fragment() {",CONVERSIONS + "\nvoid fragment() {")
			source = source.replace("vec4 t = ei_unit_tex(albedo_tex, UV);","vec4 t = ei_unit_tex(albedo_tex, UV);" + blend)
		var shader := Shader.new(); shader.code = source; programs[mode] = shader
	var m := ShaderMaterial.new(); m.shader = programs[mode]
	m.set_shader_parameter("albedo_tex",base)
	if wound: m.set_shader_parameter("wound_tex",wound)
	return m

func capture(m: ShaderMaterial, label: String) -> Image:
	draw.material_override = m
	await frames(12)
	var image := view.get_texture().get_image(); image.convert(Image.FORMAT_RGBA8)
	image.save_png("user://wound-layer-" + label + ".png")
	return image

func difference(a: Image, b: Image, healthy: Image) -> Dictionary:
	var aa := a.get_data(); var bb := b.get_data(); var hh := healthy.get_data()
	var changed := 0; var over2 := 0; var peak := 0; var signal_pixels := 0
	var error_sum := 0; var signal_sum := 0
	for i in range(0,aa.size(),4):
		var local := 0; var wound_change := 0
		for c in 3:
			var d := absi(aa[i+c]-bb[i+c]); local = maxi(local,d); error_sum += d
			var wound_delta := absi(aa[i+c]-hh[i+c]); wound_change = maxi(wound_change,wound_delta); signal_sum += wound_delta
		peak = maxi(peak,local); changed += int(local > 0); over2 += int(local > 2)
		signal_pixels += int(wound_change > 2)
	return {"different_pixels":changed,"pixels_over_2":over2,"max_channel_delta":peak,
			"reference_wound_pixels_over_2":signal_pixels,"error_sum":error_sum,"wound_signal_sum":signal_sum,
			"error_to_wound_signal":float(error_sum)/maxf(signal_sum,1)}

func specimen(mask: String, skin: String, lv: PackedByteArray) -> void:
	var base := EIUnitModel._compose(mask,[skin])
	check(base != null,"real base loads " + skin)
	if base == null: return
	var source := EIUnitModel._load_layer(mask, skin)
	var inputs := layers(mask,lv,true)
	var before := Time.get_ticks_usec(); var wound := overlay(inputs)
	var compose_us := Time.get_ticks_usec()-before
	check(wound != null,"real wound layers compose")
	if wound == null: return
	before = Time.get_ticks_usec(); var expected := baked(source,inputs)
	var bake_us := Time.get_ticks_usec()-before
	var own := source.duplicate() as Image; var resized := wound.duplicate() as Image
	if resized.get_size() != source.get_size(): resized.resize(source.get_width(),source.get_height(),Image.INTERPOLATE_BILINEAR)
	own.blend_rect(resized,Rect2i(Vector2i.ZERO,resized.get_size()),Vector2i.ZERO); own.generate_mipmaps()
	check(own.get_data() == expected.get_data(),"wound-only stage preserves native composition and baked mip oracle")
	wound.generate_mipmaps()
	resized.generate_mipmaps()
	var wound_tex := ImageTexture.create_from_image(wound)
	var sized_tex := ImageTexture.create_from_image(resized)
	var expected_tex := ImageTexture.create_from_image(expected)
	var mats := {"healthy":material(base,null,"baked"),"baked":material(expected_tex,null,"baked"),
			"encoded":material(base,wound_tex,"encoded"),"linear":material(base,wound_tex,"linear"),
			"sized":material(base,sized_tex,"sized")}
	var label := skin + "-" + lv.hex_encode()
	timings.append({"case":label,"base_size":str(source.get_size()),"overlay_size":str(wound.get_size()),
			"overlay_bytes":wound.get_data_size(),"baked_bytes":expected.get_data_size(),
			"single_overlay_compose_us":compose_us,"single_baked_compose_us":bake_us})
	for sharp in [false,true]:
		RenderingServer.global_shader_parameter_set(&"ei_unit_sharp",Vector3(1,EIUnitModel.SHARP_MIP_BIAS,0) if sharp else Vector3.ZERO)
		for pixels: int in [256,128,64,24]:
			camera.size = 2.0 * view.size.x / pixels
			var frame_label := "%s-%d-%d" % [label,int(sharp),pixels]
			var healthy := await capture(mats.healthy,frame_label+"-healthy")
			var expected_frame := await capture(mats.baked,frame_label+"-baked")
			for mode: String in ["encoded","linear","sized"]:
				var actual := await capture(mats[mode],frame_label+"-"+mode)
				var result := difference(expected_frame,actual,healthy)
				result.merge({"case":label,"sharp":sharp,"atlas_pixels":pixels,"mode":mode})
				rows.append(result); print("WOUND_LAYER_ROW ",JSON.stringify(result))

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("WOUND_LAYERS requires a renderer"); get_tree().quit(2); return
	GameData.options["confine_mouse"] = 0; GameData.options["vsync"] = 0
	GameData.options["gfx_hd_textures"] = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 120; RenderingServer.set_render_loop_enabled(true)
	Gfx.ensure_globals()
	view = SubViewport.new(); view.size = Vector2i(384,384); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	Gfx.setup_original_env(environment.environment)
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.08,0.08,0.08); view.add_child(environment)
	camera = Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(0,0,3); view.add_child(camera); camera.current = true
	draw = MeshInstance3D.new(); draw.mesh = QuadMesh.new(); (draw.mesh as QuadMesh).size = Vector2(2,2); view.add_child(draw)
	await specimen("unhuma","skin_00",PackedByteArray([1,0,0,0,0,0]))
	await specimen("unhuma","skin_14",PackedByteArray([3,1,2,0,1,3]))
	var report := {"checks":checks,"failures":failures,"rows":rows,"timings":timings,
			"renderer":RenderingServer.get_current_rendering_method(),"normal_loop":true,"production_policy_changed":false}
	FileAccess.open("user://wound-layers.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("WOUND_LAYERS ",JSON.stringify(report))
	get_tree().quit(1 if failures else 0)
