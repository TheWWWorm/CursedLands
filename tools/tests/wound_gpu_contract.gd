extends Node
## P1 independent contract probe. Default: inject proposed sampling into an old
## frozen pack. --production: exercise actual UnitWounds/material APIs instead.
## The CPU oracle implements wrap/bilinear/trilinear independently of the shader.
## It keeps base sampling in its existing color domain and wound samples UNORM.

const CONVERT := """
vec3 wound_to_encoded(vec3 c) {
	if (OUTPUT_IS_SRGB) { return c; }
	return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}
vec3 wound_to_render(vec3 c) {
	if (OUTPUT_IS_SRGB) { return c; }
	return mix(c / 12.92, pow(max((c + 0.055) / 1.055, vec3(0.0)), vec3(2.4)), step(vec3(0.04045), c));
}
"""
const OVER := """
vec4 wound_over(vec4 base, vec4 wound) {
	float a = wound.a + base.a * (1.0 - wound.a);
	vec3 rgb = (wound.rgb * wound.a + wound_to_encoded(base.rgb) * base.a * (1.0 - wound.a)) / max(a, 1e-8);
	return vec4(wound_to_render(rgb), a);
}
"""
const PROBE := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D base_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D wound_tex : filter_linear_mipmap, repeat_enable;
uniform float level = 0.0;
uniform bool alpha_output = false;
uniform float material_alpha = 1.0;
""" + CONVERT + OVER + """
void fragment() {
	vec2 uv = UV * 1.3 - vec2(0.173, 0.217);
	vec4 t = wound_over(textureLod(base_tex, uv, level), textureLod(wound_tex, uv, level));
	ALBEDO = alpha_output ? wound_to_render(vec3(t.a * material_alpha)) : t.rgb;
}
"""
const INJECT := """
uniform sampler2D wound_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool wound_enabled = true;
""" + CONVERT + OVER
const ORACLE_DISPLAY := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D oracle_tex : filter_nearest, repeat_disable;
""" + CONVERT + """
void fragment() { ALBEDO = wound_to_render(texture(oracle_tex, UV).rgb); }
"""

var checks := 0
var failures := 0
var rows := []
var sources := []
var view: SubViewport
var camera: Camera3D
var quad: MeshInstance3D
var linear_backend := false
var production := false
var precision_oracle := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func frames(count := 12) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

func capture(label: String) -> Image:
	await frames()
	var img := view.get_texture().get_image()
	if view.use_hdr_2d:
		# HDR viewport readback is linear floating point. Encode before byte
		# quantization so dark Mobile RGB10A2 steps cannot mask sampler math.
		var encoded := Image.create(img.get_width(),img.get_height(),false,Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x,y)
				encoded.set_pixel(x,y,Color(encoded_channel(c.r),encoded_channel(c.g),encoded_channel(c.b),c.a))
		img = encoded
	else: img.convert(Image.FORMAT_RGBA8)
	check(img.save_png("user://wound-contract-" + label + ".png") == OK, "capture " + label)
	return img

func digest(data: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(data)
	return h.finish().hex_encode()

func difference(a: Image, b: Image) -> Dictionary:
	var aa := a.get_data()
	var bb := b.get_data()
	var peak := 0
	var changed := 0
	var over2 := 0
	var total := 0
	for i in range(0, aa.size(), 4):
		var d := 0
		for c in 3:
			var v := absi(int(aa[i + c]) - int(bb[i + c]))
			d = maxi(d, v)
			total += v
		peak = maxi(peak, d)
		changed += int(d > 0)
		over2 += int(d > 2)
	return {"peak":peak,"changed":changed,"over2":over2,"rgb_absolute_sum":total}

func compose(mask: String, levels: PackedByteArray, human: bool) -> Image:
	var inputs := []
	var codes: Array = UnitWounds.HUMAN_CODES if human else UnitWounds.OTHER_CODES
	for i in 6:
		if levels[i] == 0:
			continue
		var name := "%s%sw%d" % [mask,codes[i],levels[i]]
		var bytes := UnitWounds._layer_bytes(name)
		inputs.append([name,null,bytes])
	var job := {"layers":inputs,"decoded":{}}
	var image := UnitWounds._compose_layer(job)
	if image:
		sources.append({"mask":mask,"levels":levels.hex_encode(),"human":human,"size":str(image.get_size()),"sha256":digest(image.get_data())})
	return image

func mip_images(image: Image) -> Array[Image]:
	var result: Array[Image] = []
	var data := image.get_data()
	for level in image.get_mipmap_count() + 1:
		var w := maxi(1,image.get_width() >> level)
		var h := maxi(1,image.get_height() >> level)
		var offset := image.get_mipmap_offset(level)
		result.append(Image.create_from_data(w,h,false,Image.FORMAT_RGBA8,data.slice(offset,offset+w*h*4)))
	return result

func linear_channel(x: float) -> float:
	return x / 12.92 if x <= 0.04045 else pow((x + 0.055) / 1.055,2.4)

func encoded_channel(x: float) -> float:
	return x * 12.92 if x <= 0.0031308 else 1.055 * pow(maxf(x,0.0),1.0/2.4)-0.055

func texel(image: Image, x: int, y: int, srgb: bool) -> Vector4:
	var c := image.get_pixel(posmod(x,image.get_width()),posmod(y,image.get_height()))
	return Vector4(linear_channel(c.r),linear_channel(c.g),linear_channel(c.b),c.a) if srgb else Vector4(c.r,c.g,c.b,c.a)

func bilinear(image: Image, uv: Vector2, srgb: bool) -> Vector4:
	var p := uv * Vector2(image.get_size()) - Vector2.ONE * 0.5
	var x := floori(p.x)
	var y := floori(p.y)
	var fx := p.x - float(x)
	var fy := p.y - float(y)
	return texel(image,x,y,srgb).lerp(texel(image,x+1,y,srgb),fx).lerp(texel(image,x,y+1,srgb).lerp(texel(image,x+1,y+1,srgb),fx),fy)

func sample_mips(images: Array[Image], uv: Vector2, level: float, srgb: bool) -> Vector4:
	var lo := clampi(floori(level),0,images.size()-1)
	var hi := mini(lo+1,images.size()-1)
	return bilinear(images[lo],uv,srgb).lerp(bilinear(images[hi],uv,srgb),level-floor(level))

func oracle(base: Array[Image], wound: Array[Image], level: float, alpha: bool, opacity: float) -> Image:
	var out := Image.create(view.size.x,view.size.y,false,Image.FORMAT_RGBA8)
	for y in view.size.y:
		for x in view.size.x:
			var uv := Vector2((x+0.5)/view.size.x,(y+0.5)/view.size.y) * 1.3 - Vector2(0.173,0.217)
			var b := sample_mips(base,uv,level,linear_backend)
			var w := sample_mips(wound,uv,level,false)
			var a := w.w + b.w * (1.0-w.w)
			var c := Vector3.ZERO
			for channel in 3:
				var bc := encoded_channel(b[channel]) if linear_backend else b[channel]
				c[channel] = a*opacity if alpha else (w[channel]*w.w+bc*b.w*(1.0-w.w))/maxf(a,1e-8)
			out.set_pixel(x,y,Color(c.x,c.y,c.z,1.0))
	return out

func synthetic_image(size: int, wound: bool) -> Image:
	var out := Image.create(size,size,false,Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var i := posmod(x + y*3,8)
			var c := Color(float(posmod(i*37,256))/255.0,float(posmod(i*67+19,256))/255.0,float(posmod(i*113+47,256))/255.0,float(i)/7.0)
			if wound:
				c = Color(float(i)/15.0,float(7-i)/15.0,float(i%3)/15.0,float(i*2)/15.0)
			out.set_pixel(x,y,c)
	out.generate_mipmaps()
	return out

func check_oracle(base: Image, wound: Image, label: String) -> void:
	var b := base.duplicate() as Image
	var w := wound.duplicate() as Image
	if not b.has_mipmaps(): b.generate_mipmaps()
	if not w.has_mipmaps(): w.generate_mipmaps()
	var shader := Shader.new()
	shader.code = PROBE
	if production:
		# Exact production composition, with explicit LOD fetch replacing only
		# derivatives so the independent CPU sampler can enumerate every texel.
		var actual: String = load("res://src/ei/unit_model.gd").get_script_constant_map()["WOUND_FETCH"]
		# Explicit trilinear oracle excludes driver anisotropy, which is tested
		# unchanged in the complete world/preview figure controls below.
		actual = actual.replace("filter_linear_mipmap_anisotropic","filter_linear_mipmap")
		shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float level = 0.0;
uniform bool alpha_output = false;
uniform float material_alpha = 1.0;
vec4 ei_unit_tex(sampler2D tex, vec2 uv) { return textureLod(tex, uv, level); }
""" + actual + """
void fragment() {
	vec2 uv = UV * 1.3 - vec2(0.173, 0.217);
	vec4 t = ei_unit_wound(ei_unit_tex(albedo_tex,uv),ei_unit_tex(wound_tex,uv));
	ALBEDO = alpha_output ? wound_to_render(vec3(t.a * material_alpha)) : t.rgb;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("albedo_tex" if production else "base_tex",ImageTexture.create_from_image(b))
	mat.set_shader_parameter("wound_tex",ImageTexture.create_from_image(w))
	if production: mat.set_shader_parameter("wound_enabled",true)
	quad.material_override = mat
	for level in [0.0,1.0,2.4]:
		for alpha in [false,true]:
			mat.set_shader_parameter("level",level)
			mat.set_shader_parameter("alpha_output",alpha)
			mat.set_shader_parameter("material_alpha",0.4)
			var tag := "%s-lod%s-%s" % [label,str(level),"alpha" if alpha else "rgb"]
			var actual := await capture(tag)
			var expected := oracle(mip_images(b),mip_images(w),level,alpha,0.4)
			expected.save_png("user://wound-contract-"+tag+"-oracle.png")
			# Pass CPU-computed encoded pixels through the same display pipeline.
			# Compatibility scene.glsl uses an approximate sRGB polynomial even
			# for unshaded ALBEDO (tonemap_inc.glsl:22), with up to 7/255 dark error.
			# This control contains no wound sampling/composition, and keeps that
			# unrelated display transform outside the sampler-math comparison.
			var oracle_shader := Shader.new()
			oracle_shader.code = ORACLE_DISPLAY
			var oracle_material := ShaderMaterial.new()
			oracle_material.shader = oracle_shader
			oracle_material.set_shader_parameter("oracle_tex",ImageTexture.create_from_image(expected))
			quad.material_override = oracle_material
			var displayed := await capture(tag+"-oracle-display")
			quad.material_override = mat
			var diff := difference(actual,displayed)
			diff.merge({"label":tag,"kind":"independent_cpu_oracle","raw_encoded_png_difference":difference(actual,expected)})
			rows.append(diff)
			# RGBA8 material output plus texture interpolation precision; no visual tolerance.
			check(diff.peak <= 2,tag+" agrees with independent encoded-UNORM oracle within 2/255")

func candidate_shader(original: Shader) -> Shader:
	var shader := Shader.new()
	shader.code = original.code.replace("void fragment() {",INJECT+"\nvoid fragment() {").replace(
		"vec4 t = ei_unit_tex(albedo_tex, UV);","vec4 t = ei_unit_tex(albedo_tex, UV); if (wound_enabled) { t = wound_over(t, ei_unit_tex(wound_tex, UV)); }")
	return shader

func material_alpha_controls() -> void:
	# A wounded transparent base crosses the authored alpha-scissor threshold.
	# Soft-alpha materials instead blend the composed coverage. The reference
	# substitutes an independently calculated constant texture result, leaving
	# the exact production material/lighting/opacity path around it unchanged.
	var b := Image.create(1,1,false,Image.FORMAT_RGBA8)
	b.fill(Color(0.7,0.45,0.3,0.25))
	var w := Image.create(1,1,false,Image.FORMAT_RGBA8)
	w.fill(Color(0.35,0.03,0.02,0.6))
	var bc := b.get_pixel(0,0)
	var wc := w.get_pixel(0,0)
	var a := wc.a+bc.a*(1.0-wc.a)
	var c := (Vector3(wc.r,wc.g,wc.b)*wc.a+Vector3(bc.r,bc.g,bc.b)*bc.a*(1.0-wc.a))/a
	var literal := "vec4 t = vec4(wound_to_render(vec3(%.9f,%.9f,%.9f)),%.9f);" % [c.x,c.y,c.z,a]
	RenderingServer.global_shader_parameter_set(&"ei_unit_sharp",Vector3.ZERO)
	for preview in [false,true]:
		for soft in [false,true]:
			var mat = EIUnitModel._material(preview,soft)
			mat.albedo_texture = ImageTexture.create_from_image(b)
			mat.wound_texture = ImageTexture.create_from_image(w)
			quad.material_override = mat
			var actual: Shader = mat.shader
			var reference := Shader.new()
			reference.code = actual.code.replace("vec4 t = ei_unit_tex(albedo_tex, UV);\n\tif (wound_enabled) { t = ei_unit_wound(t, ei_unit_tex(wound_tex, UV)); }",literal)
			for opacity in [1.0,0.4]:
				if not preview:
					if Portability.compatibility(): mat.set_shader_parameter("ei_material_diffuse",Color(1,1,1,opacity))
					else: quad.set_instance_shader_parameter("ei_material_diffuse",Color(1,1,1,opacity))
				var tag := "material-preview%d-soft%d-opacity%s" % [int(preview),int(soft),str(opacity)]
				mat.shader = actual
				var rendered := await capture(tag+"-actual")
				mat.shader = reference
				var expected := await capture(tag+"-reference")
				var diff := difference(rendered,expected)
				diff.merge({"label":tag,"kind":"production_material_alpha"})
				rows.append(diff)
				check(diff.peak<=2,"composed alpha/material opacity applied once: "+tag)
	quad.set_instance_shader_parameter("ei_material_diffuse",null)

func figure_record(mask: String) -> Dictionary:
	for proto: Dictionary in GameData.db.tables.get("monster_prototypes",[]):
		var race := GameData.db.find("race_models",String(proto.get("base_race","")))
		if String(race.get("mask","")).to_lower() == mask:
			return {"prototype":proto.get("name",""),"template":mask}
	return {"template":mask}

func figure_case(mask: String, levels: PackedByteArray, human: bool) -> void:
	quad.visible = false
	view.size = Vector2i(768,512)
	camera.position = Vector3(0,1.2,6)
	camera.look_at(Vector3(0,0.7,0))
	var wound := compose(mask,levels,human)
	var no_wounds := mask == "unmowi"
	check((wound == null) == no_wounds,"shipped wound presence " + mask)
	if no_wounds:
		wound = Image.create(1,1,false,Image.FORMAT_RGBA8)
		wound.fill(Color.TRANSPARENT)
	elif wound == null:
		return
	wound.generate_mipmaps()
	var wound_texture: ImageTexture
	if not production: wound_texture = ImageTexture.create_from_image(wound)
	var models: Array[EIUnitModel] = []
	var material_rows := []
	var record := figure_record(mask)
	if mask == "unmowi": record = {"prototype":"WillowispM1"}
	for preview in [false,true]:
		var model := EIUnitModel.create(record,preview,false)
		check(model != null,"world/preview model " + mask)
		if model == null: continue
		view.add_child(model)
		model.position.x = 0.65 if preview else -0.65
		model.act("idle",1,0.0)
		if model.player:
			model.player.seek(0.0,true)
			model.player.pause()
		model.process_mode = Node.PROCESS_MODE_DISABLED
		models.append(model)
		for m: Material in UnitWounds._materials(model):
			if m is ShaderMaterial and m.albedo_texture:
				material_rows.append([m,m.albedo_texture,m.shader,m.shader if production else candidate_shader(m.shader)])
	for sharp in [false,true]:
		RenderingServer.global_shader_parameter_set(&"ei_unit_sharp",Vector3(1,EIUnitModel.SHARP_MIP_BIAS,0) if sharp else Vector3.ZERO)
		for size in [2.2,6.6]:
			camera.size = size
			var tag := "%s-sharp%d-size%s" % [mask,int(sharp),str(size)]
			for r: Array in material_rows:
				r[0].shader = r[2]
				r[0].albedo_texture = r[1]
			for m: EIUnitModel in models:
				m.remove_meta("wound_key")
				if production: UnitWounds.apply(m,PackedByteArray([0,0,0,0,0,0]),human)
			var healthy := await capture(tag+"-healthy")
			for m: EIUnitModel in models: UnitWounds.apply(m,levels,human)
			UnitWounds.flush()
			var baked: Image
			if not production:
				baked = await capture(tag+"-baked")
				for r: Array in material_rows:
					r[0].shader = r[3]
					r[0].albedo_texture = r[1]
					r[0].set_shader_parameter("wound_tex",wound_texture)
					r[0].set_shader_parameter("wound_enabled",not no_wounds)
			var candidate := await capture(tag+"-candidate")
			var diff := difference(healthy if production else baked,candidate)
			diff.merge({"label":tag,"kind":"production_wound_signal" if production else "baked_vs_candidate","wound_signal":difference(healthy,candidate if production else baked)})
			rows.append(diff)
			if no_wounds:
				check(diff.peak == 0,"translucent no-wound control exact " + tag)
			else:
				check(diff.wound_signal.changed > 25,"real wound signal visible " + tag)
			for r: Array in material_rows:
				check(r[0].albedo_texture == r[1],"candidate retains base identity " + tag)
				r[0].shader = r[2]
			if production:
				check(UnitWounds._composites.is_empty() and UnitWounds._bases.is_empty(),"no replacement-albedo output/cache " + tag)
				for m: EIUnitModel in models: UnitWounds.apply(m,PackedByteArray([0,0,0,0,0,0]),human)
			var healed := await capture(tag+"-healed")
			check(difference(healthy,healed).peak == 0,"healthy/healed exact " + tag)
	for m: EIUnitModel in models: m.free()
	UnitWounds.shutdown()

func _ready() -> void:
	production = OS.get_cmdline_user_args().has("--production")
	precision_oracle = OS.get_cmdline_user_args().has("--precision-oracle") and RenderingServer.get_current_rendering_method() == "mobile"
	# Executed 2dintmmx.dll oracle, retained in the original UI parity receipt.
	# This digest is not computed from the new shader or its test formula.
	var native := compose("unhuma",PackedByteArray([1,2,3,1,2,3]),true)
	check(native != null and digest(native.get_data()) == "39ff45f61a681cbf03e73b32bbeb4d36c583e0da4413304d6614c114cf7a2b5a", "six-layer native DLL ARGB4444 checksum")
	if DisplayServer.get_name() == "headless":
		print("WOUND_GPU_CONTRACT_NATIVE ",JSON.stringify({"checks":checks,"failures":failures,"sources":sources}))
		get_tree().quit(1 if failures else 0)
		return
	GameData.options["gfx_hd_textures"] = 0
	GameData.options["confine_mouse"] = 0
	if OS.get_cmdline_user_args().has("--composed"):
		for key in ["gfx_water","gfx_water_interaction","gfx_water_current","gfx_water_caustics","gfx_water_reflections","gfx_terrain_cliffs","gfx_ground_contact","gfx_materials","gfx_weather_surfaces","gfx_wind"]: GameData.options[key] = 1
		GameData.options["gfx_clouds"] = 3
		GameData.options["gfx_terrain"] = 2
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Engine.max_fps = 120
	RenderingServer.set_render_loop_enabled(true)
	Gfx.ensure_globals()
	Gfx.apply_surface_options()
	Gfx.set_light(Color(0.55,0.55,0.55),Color.WHITE)
	linear_backend = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	view = SubViewport.new()
	view.size = Vector2i(64,64)
	view.own_world_3d = true
	view.use_hdr_2d = precision_oracle
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	Gfx.setup_original_env(environment.environment)
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.09,0.11,0.13)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	view.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40,-35,0)
	view.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position = Vector3(0,0,3)
	view.add_child(camera)
	camera.current = true
	quad = MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	(quad.mesh as QuadMesh).size = Vector2(2,2)
	view.add_child(quad)
	await check_oracle(synthetic_image(16,false),synthetic_image(8,true),"synthetic-alpha")
	var human_base := EIUnitModel._compose("unhuma",["skin_14"])
	await check_oracle(human_base.get_meta(UnitWounds.SOURCE_IMAGE),compose("unhuma",PackedByteArray([3,1,2,0,1,3]),true),"human-mixed")
	# All actual material and figure controls retain the shipped viewport format.
	view.use_hdr_2d = false
	if production: await material_alpha_controls()
	for spec: Array in [["unhuma",PackedByteArray([3,1,2,0,1,3]),true],["unanwibo",PackedByteArray([1,0,2,2,1,1]),false],["unmowi",PackedByteArray([1,0,2,2,1,1]),false]]:
		await figure_case(spec[0],spec[1],spec[2])
	var report := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"sources":sources,"rows":rows,"production_changed":production,"precision_oracle":precision_oracle,"policy":"Independent native-size raw-UNORM wound mip chain; existing base sampling; straight encoded RGB source-over; texture-alpha source-over with material opacity applied once, preserving remake material coverage policy."}
	FileAccess.open("user://wound-gpu-contract.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("WOUND_GPU_CONTRACT ",JSON.stringify(report))
	view.free()
	UnitWounds.shutdown()
	get_tree().quit(1 if failures else 0)
