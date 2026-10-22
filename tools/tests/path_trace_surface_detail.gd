extends "res://tools/tests/path_trace_surface_maps.gd"
## Actual GPU/import/collector checks for authored data maps. A neutral albedo
## proves that normal and metal information comes from the explicit map.
const DETAIL_SHADER := """
shader_type spatial;
uniform sampler2D albedo_tex : source_color;
uniform sampler2D surface_detail_tex;
uniform bool surface_detail_enabled = true;
uniform vec4 surface_profile = vec4(0.2,0.9,0.0,0.06);
void fragment() { ALBEDO = texture(albedo_tex,UV).rgb; }
"""

func normal_at(point: Vector3) -> Vector3:
	var c:=sample(device.guide,point)
	return Vector3(c.r,c.g,c.b)

func fixture(mirror:=false,degenerate:=false) -> ArrayMesh:
	var quad:=QuadMesh.new();quad.size=Vector2(20,20)
	var arrays:=quad.surface_get_arrays(0)
	var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	for i in uv.size():
		if mirror:uv[i].x=1.0-uv[i].x
		if degenerate:uv[i]=Vector2(0.5,0.5)
	arrays[Mesh.ARRAY_TEX_UV]=uv
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func raster_normal(mesh: Mesh,packed: Texture2D,xform:=Transform3D.IDENTITY,back:=false) -> Vector3:
	var viewport:=SubViewport.new();viewport.size=Vector2i(320,180);viewport.own_world_3d=true
	viewport.use_hdr_2d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var eye:=Camera3D.new();viewport.add_child(eye);eye.current=true
	eye.projection=Camera3D.PROJECTION_ORTHOGONAL;eye.size=8
	eye.position=Vector3(0,0,-6 if back else 6);eye.look_at(Vector3.ZERO)
	var shader:=Shader.new();shader.code="shader_type spatial; render_mode unshaded,cull_disabled;\n"+SurfaceDetail.SHADER+"""
void fragment() {
	vec3 n=NORMAL;
	n=ei_surface_detail_normal(texture(surface_detail_tex,UV).rg,UV,VERTEX,n,VIEW,1.0);
	ALBEDO=(mat3(INV_VIEW_MATRIX)*n)*0.5+0.5;
}
"""
	var material:=ShaderMaterial.new();material.shader=shader
	material.set_shader_parameter("surface_detail_tex",packed)
	var instance:=MeshInstance3D.new();instance.mesh=mesh;instance.material_override=material;instance.transform=xform
	viewport.add_child(instance);await frames(8);await RenderingServer.frame_post_draw
	var im:=viewport.get_texture().get_image();var c:=im.get_pixel(160,90)
	var result:=Vector3(c.r,c.g,c.b)*2-Vector3.ONE
	viewport.queue_free();await frames(4)
	return result

func build_transformed(scene: RefCounted,xform: Transform3D) -> bool:
	if device!=null:RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	device=PathDevice.new();tick=0
	RenderingServer.call_on_render_thread(device.build.bind(scene.vertices.to_byte_array(),scene.images,
		scene.geometries,[{"geometry":0,"transform":xform,"mask":7}]))
	return await device.prepared

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified path-tracing device")
	if not PathDevice.supported():finish();return
	GameData.options.gfx_materials=1
	var maps:={}
	for name: String in SurfaceDetail.SOURCES:
		var source:=GameData.textures.read(name+".mmp")
		check(SurfaceDetail.matches_source(name,source),"verified original atlas "+name)
		check(not SurfaceDetail.matches_source(name,source.slice(0,source.size()-1)),"changed source rejects mismatched regions "+name)
		var tex:=load("res://assets/materials/surface-detail/%s.png"%name) as Texture2D
		check(tex!=null,"export includes authored map "+name)
		if tex==null:continue
		var im:=tex.get_image();maps[name]=im
		var p:=im.get_pixel(256,256)
		check(im.get_size()==Vector2i(512,512) and im.has_mipmaps(),"lossless data map retains mip chain "+name)
		check(p.r>0.2 and p.g>0.2 and p.b>0.25,"import preserves RGB even where metalness alpha is zero "+name)
	if maps.has("bridge00"):
		var bone: Color=maps.bridge00.get_pixel(87,415)
		check(absf(bone.r-0.5)<0.005 and absf(bone.g-0.5)<0.005 and bone.a==0,"bridge bone ornament stays smooth and dielectric")
		var bone_source: Color=GameData.load_image("bridge00").get_pixel(43,207)
		check(bone_source.r>0.95 and bone_source.g>0.9 and bone_source.b>0.75,"smooth bone region matches the runtime albedo row orientation")
	if maps.has("stone03"):
		var snow: Color=maps.stone03.get_pixel(205,13)
		var snow_source: Color=GameData.load_image("stone03").get_pixel(102,6)
		check(snow_source.r>0.8 and snow_source.g>0.8 and snow_source.b>0.8 and absf(snow.r-0.5)<0.005 and absf(snow.g-0.5)<0.005,
			"snow mask and neutral normal align to the decoded original texture")
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var packed:=Image.create(2,2,false,Image.FORMAT_RGBA8);packed.fill(Color(0.8,0.65,0.4,1))
	var shader:=Shader.new();shader.code=DETAIL_SHADER
	var material:=ShaderMaterial.new();material.shader=shader
	material.set_shader_parameter("albedo_tex",ImageTexture.create_from_image(white))
	material.set_shader_parameter("surface_detail_tex",ImageTexture.create_from_image(packed))
	material.set_shader_parameter("surface_detail_enabled",true)
	var scene:=collect(fixture(),material);var scripted:=collect(fixture(),material,true)
	check(scene.geometries==scripted.geometries and scene.vertices==scripted.vertices,"native and script collectors agree on detail maps")
	check(scene.images.size()==2 and scene.geometries[0].detail_layer==1,"detail map uses one existing array layer")
	camera=Camera3D.new();add_child(camera);camera.current=true
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=8
	camera.position=Vector3(0,0,6);camera.look_at(Vector3.ZERO)
	sun_energy=0;sky_energy=1;bounces=2
	var expected:=Vector3(0.6,-(166.0/255.0*2.0-1.0),0)
	expected.z=sqrt(1.0-expected.x*expected.x-expected.y*expected.y)
	var readings:=[]
	for choice: Array in [[false,false],[true,false],[false,true]]:
		check(await build_map(collect(fixture(choice[0],choice[1]),material)),"build normal fixture "+str(choice))
		await render_many(4)
		var n:=normal_at(Vector3.ZERO);var target:=expected
		if choice[0]:target.x=-target.x
		if choice[1]:target=Vector3.BACK
		readings.append({"case":choice,"normal":str(n),"expected":str(target)})
		check(n.distance_to(target)<0.015,"GPU respects tangent orientation or degenerate fallback "+str(choice)+": "+str(n))
		var properties:=material_at(Vector3.ZERO)
		check(absf(properties.x-0.4)<0.012 and properties.y>0.99,"GPU consumes packed roughness and metalness "+str(choice))
		var raster:=await raster_normal(fixture(choice[0],choice[1]),material.get_shader_parameter("surface_detail_tex"))
		check(n.distance_to(raster)<0.02,"raster and ray normals agree "+str(choice)+": "+str(raster))
	for reflected: bool in [false,true]:
		var basis:=Basis(Vector3.BACK,0.4).scaled(Vector3(-1.5 if reflected else 1.5,0.6,1.0))
		var transform:=Transform3D(basis,Vector3.ZERO)
		check(await build_transformed(collect(fixture(),material),transform),"build rotated nonuniform instance "+str(reflected))
		await render_many(4)
		var n:=normal_at(Vector3.ZERO)
		var raster:=await raster_normal(fixture(),material.get_shader_parameter("surface_detail_tex"),transform)
		check(n.distance_to(raster)<0.02 and n.z>0.65,"instance transforms preserve raster/ray basis parity "+str(reflected)+": "+str(n)+" / "+str(raster))
	# The same tangent convention is valid from behind a two-sided surface.
	check(await build_map(collect(fixture(),material)),"build back-facing normal fixture")
	camera.position.z=-6;camera.look_at(Vector3.ZERO);await render_many(4)
	var back:=expected;back.z=-back.z
	check(normal_at(Vector3.ZERO).distance_to(back)<0.015,"back-face normal stays in the visible geometry hemisphere")
	var raster_back:=await raster_normal(fixture(),material.get_shader_parameter("surface_detail_tex"),Transform3D.IDENTITY,true)
	check(normal_at(Vector3.ZERO).distance_to(raster_back)<0.02,"raster and ray back-face normals agree: "+str(raster_back))
	camera.position.z=80;camera.look_at(Vector3.ZERO);await render_many(2)
	check(normal_at(Vector3.ZERO).distance_to(Vector3.BACK)<0.001 and material_at(Vector3.ZERO).x>=0.63,
		"distance fades normal detail and broadens unresolved highlights")
	camera.position.z=6;camera.look_at(Vector3.ZERO)
	camera.size=160;await render_many(2)
	check(normal_at(Vector3.ZERO).distance_to(Vector3.BACK)<0.001 and material_at(Vector3.ZERO).x>=0.63,
		"minification fades unresolved normals without dropping metalness")
	camera.size=8
	var version: Array=scene._material_version(material)
	material.set_shader_parameter("surface_detail_enabled",false)
	check(version!=scene._material_version(material),"detail enable change invalidates the material snapshot")
	var disabled:=collect(fixture(),material)
	check(disabled.images.size()==1 and disabled.geometries[0].detail_layer<0,"disabled detail uses scalar fallback without map upload")
	material.set_shader_parameter("surface_detail_enabled",true);GameData.options.gfx_materials=0
	disabled=collect(fixture(),material)
	check(disabled.images.size()==1 and disabled.geometries[0].detail_layer<0,"material-effects option disables authored detail collection")
	check(await build_map(disabled),"build disabled material fixture")
	await render_many(2)
	check(normal_at(Vector3.ZERO).distance_to(Vector3.BACK)<0.001 and material_at(Vector3.ZERO).y==0,"disabled material effects restore flat dielectric response")
	FileAccess.open(out.path_join("path-surface-detail.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"readings":readings},"\t"))
	RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	camera.queue_free();await frames();finish()
