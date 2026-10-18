extends Node
## Render the original relief formula against the optimized one, including
## distance and minification cutoffs crossing neighbouring fragment lanes.
const SIZE := Vector2i(384,320)
const REFERENCE := """
#ifndef EI_NO_MATERIALS
vec3 ei_relief_normal(sampler2D tex, vec2 uv, vec3 p, vec3 n, float strength) {
	vec2 size = vec2(textureSize(tex, 0));
	vec2 dx = dFdx(uv) * size;
	vec2 dy = dFdy(uv) * size;
	float visible_detail = 1.0 - smoothstep(1.2, 4.0, max(length(dx), length(dy)));
	visible_detail *= 1.0 - smoothstep(14.0, 40.0, length(p));
	vec2 px = 1.0 / size;
	vec3 lum = vec3(0.2126, 0.7152, 0.0722);
	float left = dot(texture(tex, uv - vec2(px.x, 0.0)).rgb, lum);
	float right = dot(texture(tex, uv + vec2(px.x, 0.0)).rgb, lum);
	float above = dot(texture(tex, uv - vec2(0.0, px.y)).rgb, lum);
	float below = dot(texture(tex, uv + vec2(0.0, px.y)).rgb, lum);
	vec2 slope = clamp(vec2(right - left, below - above) * 2.0, vec2(-0.12), vec2(0.12));
	vec3 dpdx = dFdx(p);
	vec3 dpdy = dFdy(p);
	vec2 duvdx = dFdx(uv);
	vec2 duvdy = dFdy(uv);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	vec3 u = r1 * duvdx.x + r2 * duvdy.x;
	vec3 v = r1 * duvdx.y + r2 * duvdy.y;
	float scale = inversesqrt(max(max(dot(u, u), dot(v, v)), 1e-12));
	return normalize(n - (u * slope.x + v * slope.y) * scale * strength * visible_detail);
}
#endif
"""
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("FAIL ",message)

func capture(view: SubViewport) -> Image:
	for i in 6: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result := view.get_texture().get_image()
	result.convert(Image.FORMAT_RGBA8)
	return result

func difference(a: Image,b: Image) -> Dictionary:
	var aa := a.get_data(); var bb := b.get_data()
	var peak := 0; var changed := 0
	for i in range(0,aa.size(),4):
		var delta := 0
		for channel in 3: delta=maxi(delta,absi(int(aa[i+channel])-int(bb[i+channel])))
		peak=maxi(peak,delta)
		if delta>1: changed+=1
	return {"peak":peak,"over_one_byte":changed}

func shader(relief: String) -> Shader:
	var result := Shader.new()
	result.code="""shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform sampler2D art : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float distance_shift = 0.0;
uniform float uv_scale = 1.0;
uniform float relief_strength = 1.0;
"""+relief+"""
void fragment() {
	vec3 n=ei_relief_normal(art,UV*uv_scale,VERTEX-vec3(0.0,0.0,distance_shift),NORMAL,relief_strength);
	ALBEDO=n*0.5+0.5;
}
"""
	return result

func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"vsync":0,"fps_limit":0},true)
	await get_tree().process_frame
	var view := SubViewport.new();view.size=SIZE;view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var camera:=Camera3D.new();camera.position=Vector3(0,0,8);camera.current=true;view.add_child(camera)
	var surface:=MeshInstance3D.new();surface.mesh=QuadMesh.new();surface.mesh.size=Vector2(6,6)
	surface.rotation_degrees=Vector3(28,18,0);view.add_child(surface)
	var pixels:=Image.create(64,64,false,Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var value:=0.5+0.45*sin(x*0.43)*cos(y*0.37)
			pixels.set_pixel(x,y,Color(value,value,value,1))
	pixels.generate_mipmaps()
	var material:=ShaderMaterial.new();surface.material_override=material
	var before:=shader(REFERENCE);var after:=shader(SurfaceMaterials.RELIEF_SHADER)
	material.shader=before;material.set_shader_parameter("art",ImageTexture.create_from_image(pixels))
	var rows:=[]
	var witness:=false
	for aa in [Viewport.MSAA_DISABLED,Viewport.MSAA_4X]:
		view.msaa_3d=aa
		for settings:Vector2 in [Vector2(0,1),Vector2(5,1),Vector2(18,1),Vector2(31,1),Vector2(32,1),Vector2(60,1),Vector2(0,6),Vector2(0,8),Vector2(0,16),Vector2(0,24),Vector2(0,32)]:
			material.set_shader_parameter("distance_shift",settings.x);material.set_shader_parameter("uv_scale",settings.y)
			material.shader=before;var reference:=await capture(view)
			material.shader=after;var candidate:=await capture(view)
			var delta:=difference(reference,candidate)
			check(delta.peak<=1,"relief pixels match at AA/depth/scale "+str([aa,settings,delta]))
			rows.append({"msaa":aa,"depth_shift":settings.x,"uv_scale":settings.y,"difference":delta})
			if settings==Vector2(0,1):
				material.set_shader_parameter("relief_strength",0.0);var flat:=await capture(view)
				material.set_shader_parameter("relief_strength",1.0)
				var control:=difference(reference,flat)
				witness=witness or control.over_one_byte>500
	check(witness,"the fixture contains visible relief")
	FileAccess.open("user://surface-relief.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"rows":rows},"\t"))
	print("SURFACE_RELIEF ",checks," checks; failures=",JSON.stringify(failures))
	view.free();TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
