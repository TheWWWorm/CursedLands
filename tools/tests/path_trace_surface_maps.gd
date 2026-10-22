extends "res://tools/tests/path_trace_device.gd"
## Exercise the real collector and native GPU shader. Material identity comes
## from equipment masks while the colour texture stays identical on both sides.
const Scene = preload("res://src/game/fx/water_raytrace_scene.gd")
const Surface = preload("res://src/game/surface_materials.gd")
const MATERIAL_SHADER := """
shader_type spatial;
uniform sampler2D albedo_tex : source_color;
uniform sampler2D surface_tex;
uniform vec4 ei_material_diffuse = vec4(1.0);
uniform vec3 ei_material_emissive = vec3(0.0);
void fragment() { ALBEDO = texture(albedo_tex, UV).rgb; ROUGHNESS = texture(surface_tex, UV).g; }
"""

func collect(mesh: Mesh,material: ShaderMaterial,script:=false) -> RefCounted:
	var scene:=Scene.new();scene.path_materials=true;scene.lighting_camera_mask=1
	if script:scene._kernel=null
	scene._append(mesh.surface_get_arrays(0),Transform3D.IDENTITY,material,false)
	return scene

func build_map(scene: RefCounted) -> bool:
	if device!=null:
		RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	device=PathDevice.new();tick=0
	RenderingServer.call_on_render_thread(device.build.bind(scene.vertices.to_byte_array(),scene.images,
		scene.geometries,[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7}]))
	return await device.prepared

func material_at(point: Vector3) -> Vector2:
	var code:=int(roundf(sample(device.shadow1,point).a))
	return Vector2(float(code&63)/63.0,float(code>>6)/31.0)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified path-tracing device")
	if not PathDevice.supported():finish();return
	GameData.options.gfx_materials=1
	var white:=Image.create(16,16,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var mask:=Image.create(16,16,false,Image.FORMAT_RGBA8)
	var metal:=Surface.equipment({"type":"metal"});var skin:=Surface.SKIN
	mask.fill(Color(skin.x,skin.y,skin.z))
	mask.fill_rect(Rect2i(0,0,8,16),Color(metal.x,metal.y,metal.z))
	var shader:=Shader.new();shader.code=MATERIAL_SHADER
	var material:=ShaderMaterial.new();material.shader=shader
	material.set_shader_parameter("albedo_tex",ImageTexture.create_from_image(white))
	material.set_shader_parameter("surface_tex",ImageTexture.create_from_image(mask))
	var mesh:=QuadMesh.new();mesh.size=Vector2(3,3)
	var scene:=collect(mesh,material);var scripted:=collect(mesh,material,true)
	check(scene.geometries.size()==1 and not scene.failed,"collector retains the mapped receiver")
	if scene.geometries.is_empty():finish();return
	var layer: int=scene.geometries[0].get("surface_layer",-1)
	check(layer>=0 and scene.images.size()==2,"surface map shares the existing texture array")
	check(scene.vertices==scripted.vertices and scene.geometries==scripted.geometries,"native and script packing preserve the same material map")
	if layer<0:finish();return
	var texel: Color=scene.images[layer].get_pixel(64,256)
	check(absf(texel.g-metal.y)<0.005 and absf(texel.b-metal.z)<0.005,"roughness and metalness remain linear data")
	camera=Camera3D.new();add_child(camera);camera.current=true
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4
	camera.position=Vector3(0,0,6);camera.look_at(Vector3.ZERO)
	sun_energy=0;sky_energy=1;bounces=2
	check(await build_map(scene),"build native mapped-material pipeline")
	await render_many(24)
	var left:=Vector3(-0.75,0,0);var right:=Vector3(0.75,0,0)
	var metal_code:=material_at(left);var skin_code:=material_at(right)
	check(absf(metal_code.x-metal.y)<0.012 and absf(metal_code.y-metal.z)<0.02,"GPU samples the equipment's rough metal region")
	check(absf(skin_code.x-skin.y)<0.012 and skin_code.y==0,"GPU preserves exposed dielectric skin")
	var metal_diffuse:=sample(device.output,left);var skin_diffuse:=sample(device.output,right)
	var metal_glossy:=sample(device.shadow0,left);var skin_glossy:=sample(device.shadow0,right)
	check(metal_diffuse.r<skin_diffuse.r*0.25,"material mask visibly reduces the metal diffuse lobe")
	check(metal_glossy.r>skin_glossy.r*3.0,"metal reflects substantially more sky than skin")
	device.output.get_image().save_exr(out.path_join("mapped-diffuse.exr"))
	device.shadow0.get_image().save_exr(out.path_join("mapped-glossy.exr"))
	device.shadow1.get_image().save_exr(out.path_join("mapped-material.exr"))
	var version: Array=scene._material_version(material)
	var changed:=mask.duplicate();changed.fill(Color(skin.x,skin.y,skin.z))
	material.set_shader_parameter("surface_tex",ImageTexture.create_from_image(changed))
	check(version!=scene._material_version(material),"equipment mask replacement invalidates material identity with unchanged albedo")
	check(await build_map(collect(mesh,material)),"rebuild changed equipment material")
	await render_many(2)
	check(material_at(left).y==0,"replaced equipment no longer leaves a metallic region")
	GameData.options.gfx_materials=0
	var disabled:=collect(mesh,material)
	check(disabled.geometries[0].surface_layer<0 and disabled.images.size()==1,"disabled material effects avoid mask storage and sampling")
	check(await build_map(disabled),"build scalar material fallback")
	await render_many(2)
	check(material_at(left)==Vector2(1,0),"disabled option restores the rough dielectric fallback")
	FileAccess.open(out.path_join("path-surface-maps.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,
		"metal_material":str(metal_code),"skin_material":str(skin_code),"metal_diffuse":str(metal_diffuse),"skin_diffuse":str(skin_diffuse),
		"metal_glossy":str(metal_glossy),"skin_glossy":str(skin_glossy),"mapped_layers":scene.images.size()},"\t"))
	RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	camera.queue_free();await frames();finish()
