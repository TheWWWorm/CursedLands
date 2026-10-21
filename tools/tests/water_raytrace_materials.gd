extends "res://tools/tests/water_raytrace_lighting.gd"
## Independent GPU expectations for opacity, cutout, tint and emission.
const Scene = preload("res://src/game/fx/water_raytrace_scene.gd")
const RECEIVER = [Vector3(-3,0.4,0),Vector3(3,0.4,0),Vector3(0,5,0)]
const BLOCKER = [Vector3(0.6,-1,1),Vector3(2.4,-1,1),Vector3(1.5,7,1)]

func texture(colour: Color) -> ImageTexture:
	var im := Image.create(2,2,false,Image.FORMAT_RGBA8); im.fill(colour)
	return ImageTexture.create_from_image(im)

func standard(colour: Color, mode: int, cutoff := 0.5, alpha := 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new(); mat.albedo_texture=texture(colour)
	mat.transparency=mode; mat.alpha_scissor_threshold=cutoff; mat.albedo_color.a=alpha
	return mat

func append(scene: Scene, points: Array, mat: Material, transform := Transform3D.IDENTITY, land := false) -> int:
	var a := []; a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX]=PackedVector3Array(points)
	a[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK])
	a[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(0.5,0.5),Vector2(0.5,0.5),Vector2(0.5,0.5)])
	a[Mesh.ARRAY_TEX_UV2]=PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])
	return scene._append(a,transform,mat,land)

func build_scene(scene: Scene, fast: bool) -> Device:
	var device := Device.new(); device._opaque_fast_path=fast
	var placements := []
	for i in scene.geometries.size(): placements.append({"geometry":i,"transform":Transform3D.IDENTITY})
	RenderingServer.call_on_render_thread(device.build.bind(scene.vertices.to_byte_array(),scene.images,scene.geometries,placements))
	var ok: bool=await device.prepared; check(ok,"material scene prepares, opaque fast path="+str(fast))
	return device

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out=" ): out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(Device.supported(),"qualified Vulkan RT runtime is available")
	if not Device.supported(): finish(); return
	var camera := Camera3D.new(); add_child(camera)
	camera.position=Vector3(0,-1,3); camera.look_at(Vector3(0,1.5,0)); camera.current=true
	var frame := PackedFloat32Array()
	for matrix: Projection in [camera.get_camera_projection().inverse(),Projection(camera.global_transform)]:
		for axis in 4:
			for component in 4: frame.append(matrix[axis][component])
	frame.resize(88); frame[32]=1; frame[33]=1; frame[34]=1; frame[44]=90; frame[45]=100; frame[46]=100
	var solid := BaseMaterial3D.TRANSPARENCY_DISABLED; var cutout := BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var red := Color(1,0,0,0.6)
	var tinted := standard(Color.WHITE,solid); tinted.albedo_color=Color.RED
	var emissive := standard(Color.BLACK,solid); emissive.emission_enabled=true; emissive.emission=Color.BLUE; emissive.emission_energy_multiplier=2.0
	var legacy := ShaderMaterial.new(); var shader := Shader.new()
	shader.code="shader_type spatial; uniform sampler2D albedo_tex; uniform vec4 ei_material_diffuse=vec4(1.0); uniform vec3 ei_material_emissive=vec3(0.0); void fragment(){ ALBEDO=texture(albedo_tex,UV).rgb; }"
	legacy.shader=shader; legacy.set_shader_parameter("albedo_tex",texture(Color.RED))
	var faint := legacy.duplicate(); faint.set_shader_parameter("ei_material_diffuse",Vector4(1,1,1,0.2))
	var cases := [
		["opaque ignores texture/material alpha",standard(Color(1,0,0,0),solid,0.5,0.0),true,true],
		["low cutout accepts partial alpha",standard(red,cutout,0.25),true,false],
		["high cutout reveals rear surface",standard(red,cutout,0.8),false,false],
		["cutout multiplies material alpha",standard(red,cutout,0.4,0.5),false,false],
		["zero cutoff accepts zero alpha",standard(Color(1,0,0,0),cutout,0.0),true,true],
		["opaque cutout texture can skip any-hit",standard(Color.RED,cutout),true,true],
		["standard tint applies in ambient light",tinted,true,true],
		["standard emission survives a black albedo",emissive,true,true],
		["opaque legacy texture can skip any-hit",legacy,true,true],
		["faint legacy material remains cutout",faint,false,false]]
	for item: Array in cases:
		var scene := Scene.new(); append(scene,RECEIVER,item[1])
		check(scene.geometries[0].opaque==item[3],item[0]+": conservative opacity classification")
		append(scene,RECEIVER,standard(Color.GREEN,solid),Transform3D(Basis.IDENTITY,Vector3(0,0,-1)))
		var colours := []
		for fast in [false,true]:
			var device := await build_scene(scene,fast)
			var p := await pixels(device,frame); colours.append(p)
			print("MATERIAL_PIXEL ",item[0]," fast=",fast," colour=",p)
			if item[1]==emissive: check(p.b>1.8 and p.r<0.01 and p.g<0.01,item[0]+": linear HDR emission")
			else: check(p.r>0.99 and p.g<0.01 if item[2] else p.g>0.99 and p.r<0.01,item[0]+": expected nearest surface/colour")
			RenderingServer.call_on_render_thread(device.dispose); await frames(3)
			check(device._owned.is_empty(),"material buffer and acceleration structures released")
			check(scene.geometries.size()==2,"GPU teardown preserves the caller's scene descriptors")
		check(colours[0].is_equal_approx(colours[1]),item[0]+": fast and conservative GPU paths agree")
	for mode in [BaseMaterial3D.TRANSPARENCY_ALPHA,BaseMaterial3D.TRANSPARENCY_ALPHA_HASH,BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS]:
		var scene := Scene.new()
		check(append(scene,RECEIVER,standard(Color.RED,mode))<0 and scene.vertices.is_empty(),"unsupported blended/hashed material is omitted, mode="+str(mode))
	var sun := frame.duplicate(); sun[32]=0.12; sun[33]=0.12; sun[34]=0.12
	sun[36]=1; sun[37]=1; sun[38]=1; sun[39]=1; sun[40]=sqrt(0.5); sun[42]=sqrt(0.5)
	for item: Array in [[standard(Color(1,0,0,0),solid),true],[standard(red,cutout,0.8),false],[standard(red,cutout,0.25),true]]:
		var scene := Scene.new(); append(scene,RECEIVER,standard(Color.WHITE,solid)); append(scene,BLOCKER,item[0])
		for fast in [false,true]:
			var device := await build_scene(scene,fast); var p := await pixels(device,sun)
			print("MATERIAL_SHADOW fast=",fast," expected=",item[1]," colour=",p)
			check(p.r<0.04 if item[1] else p.r>0.35,"shadow ray obeys material opacity and cutoff; shadow="+str(item[1]))
			RenderingServer.call_on_render_thread(device.dispose); await frames(3)
	# Terrain texture alpha is not used by the raster land shader.
	var terrain := EITerrain.new(); var atlas := Texture2DArray.new()
	var im := Image.create(2,2,false,Image.FORMAT_RGBA8); im.fill(Color(0,0,1,0))
	var atlas_images: Array[Image]=[im]; atlas.create_from_images(atlas_images); terrain._atlases=atlas
	var scene := Scene.new(); scene._terrain=terrain; append(scene,RECEIVER,null,Transform3D.IDENTITY,true)
	for fast in [false,true]:
		var device := await build_scene(scene,fast); var p := await pixels(device,frame)
		check(p.b>0.99 and p.a>0.99,"terrain ignores atlas alpha; fast="+str(fast))
		RenderingServer.call_on_render_thread(device.dispose); await frames(3)
	terrain.free(); camera.queue_free(); await frames(3); finish()
