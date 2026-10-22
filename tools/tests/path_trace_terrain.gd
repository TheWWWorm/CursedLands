extends "res://tools/tests/path_trace_quality.gd"
## Native DXR/Vulkan hit materials versus the actual raster GLSL sampler.
const Transition = preload("res://src/game/fx/terrain_transition_shader.gd")
const Cliff = preload("res://src/game/fx/terrain_cliff_shader.gd")
var atlas: Texture2DArray
var tile_texture: ImageTexture
var transition_texture: ImageTexture
var cliff_texture: ImageTexture
var guard_texture: ImageTexture
var normal_texture: Image
var reference_image: Image
var mode := 0 # detailed, pair, junction, cliff
var rotation := 0
var tile_index := 0
var atlas_axis := 2
var atlas_padding := 0.125
var ground_type := 2
var use_normal := false
var land_size := Vector2i.ONE
var land_cell := Vector2i.ZERO
var offset := Vector3.ZERO
var fixture_size := Vector2i(160,90)

func uniforms(type: int,binding: int,ids: Array[RID]) -> RDUniform:
	var u:=RDUniform.new();u.uniform_type=type;u.binding=binding
	for rid in ids:u.add_id(rid)
	return u

func reference_code() -> String:
	var code:=GroundSurfaceShader.TILE_FUNCTIONS
	if mode in [1,2]:code=Transition.source(code,mode==2)
	code=code.replace("uniform sampler2D transition_tiles : filter_nearest, repeat_disable;","layout(set=0,binding=3) uniform sampler2D transition_tiles;")
	code=code.replace("uniform int transition_junction_materials = 4;","const int transition_junction_materials = 4;")
	code=code.replace("uniform int transition_relief_passes = 4;","const int transition_relief_passes = 4;")
	if mode==3:
		code+=Cliff.FUNCTIONS.replace("uniform sampler2D cliff_tiles : filter_nearest, repeat_disable;","layout(set=0,binding=4) uniform sampler2D cliff_tiles;").replace("uniform sampler2D cliff_flatness : filter_nearest, repeat_disable;","layout(set=0,binding=5) uniform sampler2D cliff_flatness;")
		code=code.replace("vec3 wx=dFdx(world); vec3 wy=dFdy(world);","vec3 wx=vec3(params.projection.z,0,0); vec3 wy=vec3(0,-params.projection.w,0);")
	var result:="""#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(rgba16f,set=0,binding=0) uniform writeonly image2D result_image;
layout(set=0,binding=1) uniform sampler2DArray atlases;
layout(set=0,binding=2) uniform sampler2D terrain_tiles;
layout(push_constant,std430) uniform Params { vec4 projection; vec4 origin; } params;
const float tiles_per_axis=2.0;
const float atlas_padding=0.125;
const float source_texel=1.0/128.0;
const bool blend_edges=true;
"""+code+"""
void main() {
 ivec2 at=ivec2(gl_GlobalInvocationID.xy),size=imageSize(result_image);
 if(any(greaterThanEqual(at,size)))return;
 vec2 uv=(vec2(at)+0.5)/vec2(size);
 vec2 point=(uv*2.0-1.0)*vec2(params.projection.x,-params.projection.y);
 vec2 p=(point+2.0)/4.0;
 vec4 traits;vec3 colour=ground_sample(ivec2(0),p,vec2(params.projection.z/4.0,0),vec2(0,-params.projection.w/4.0),traits);
"""
	if mode==3:result+="vec3 world=vec3(point,0)+params.origin.xyz;vec3 planes=cliff_weights(ivec2(0),clamp(p,vec2(0),vec2(1)),vec3(0,0,1),72.0);colour=cliff_albedo(colour,ivec2(0),clamp(p,vec2(0),vec2(1)),world,planes);\n"
	result=result.replace("const float tiles_per_axis=2.0;","const float tiles_per_axis=%s;"%float(atlas_axis))
	result=result.replace("const float atlas_padding=0.125;","const float atlas_padding=%s;"%atlas_padding)
	result=result.replace("const float source_texel=1.0/128.0;","const float source_texel=1.0/%s;"%float(atlas_axis*64))
	return result+"imageStore(result_image,at,vec4(colour,1));}\n"

func reference_render(source: String,params: PackedByteArray) -> void:
	var rd:=device._rd;var shader_source:=RDShaderSource.new();shader_source.source_compute=source
	var spirv:=rd.shader_compile_spirv_from_source(shader_source)
	var error:=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty():printerr("REFERENCE ERROR ",error);filtered.emit.call_deferred();return
	var shader:=rd.shader_create_from_spirv(spirv);var pipeline:=rd.compute_pipeline_create(shader)
	var fmt:=RDTextureFormat.new();fmt.width=size.x;fmt.height=size.y;fmt.format=RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var target:=rd.texture_create(fmt,RDTextureView.new())
	var bindings: Array[RDUniform]=[uniforms(RenderingDevice.UNIFORM_TYPE_IMAGE,0,[target])]
	for row in [[1,atlas,true],[2,tile_texture,false]]+([[3,transition_texture,false]] if mode in [1,2] else [])+([[4,cliff_texture,false],[5,guard_texture,false]] if mode==3 else []):
		bindings.append(uniforms(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,row[0],[device._samplers[0],RenderingServer.texture_get_rd_texture(row[1].get_rid(),row[2])]))
	var set:=rd.uniform_set_create(bindings,shader,0)
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set,0)
	rd.compute_list_set_push_constant(list,params,params.size());rd.compute_list_dispatch(list,ceili(size.x/8.0),ceili(size.y/8.0),1);rd.compute_list_end()
	reference_image=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAH,rd.texture_get_data(target,0))
	for rid in [set,pipeline,shader,target]:rd.free_rid(rid)
	filtered.emit.call_deferred()

func build_land() -> bool:
	if device!=null:RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	device=PathDevice.new();mesh_data.clear()
	var corners: Array[Vector3]=[Vector3(-2,-2,0),Vector3(2,-2,0),Vector3(2,2,0),Vector3(-2,2,0)]
	quad(mesh_data,corners,Vector3.BACK,Vector3.ZERO)
	for i in 6:
		var local:=(Vector2(mesh_data[i*16],mesh_data[i*16+1])+Vector2(2,2))/4.0
		var p:=(local-Vector2(0.5,0.5)).rotated(rotation*PI/2)+Vector2(0.5,0.5)
		mesh_data[i*16+3]=(tile_index%atlas_axis+0.125+p.x*0.75)/atlas_axis
		mesh_data[i*16+7]=(atlas_axis-1-tile_index/atlas_axis+0.875-p.y*0.75)/atlas_axis
		mesh_data[i*16]+=offset.x;mesh_data[i*16+1]+=offset.y;mesh_data[i*16+2]+=offset.z
	var tile_pixels:=roundi(64*(1+2*atlas_padding));var atlas_pixels:=tile_pixels*atlas_axis
	var pixels:=Image.create(atlas_pixels,atlas_pixels,true,Image.FORMAT_RGBA8)
	for y in atlas_pixels:
		for x in atlas_pixels:
			var tile:=x/tile_pixels+(atlas_axis-1-y/tile_pixels)*atlas_axis
			var local_x:=(x%tile_pixels+0.5)/tile_pixels;var local_y:=(y%tile_pixels+0.5)/tile_pixels
			pixels.set_pixel(x,y,[Color(0.2+0.5*local_x,0.15+0.2*local_y,0.15),Color(0.1,0.65,0.15),Color(0.15,0.2,0.7),Color(0.7,0.7,0.2)][tile%4])
	pixels.generate_mipmaps();atlas=Texture2DArray.new();atlas.create_from_images([pixels])
	var white:=Image.create(64,64,true,Image.FORMAT_RGBA8);white.fill(Color.WHITE);white.generate_mipmaps()
	normal_texture=white.duplicate();normal_texture.fill(Color(0.75,0.5,1));normal_texture.generate_mipmaps()
	var images: Array[Image]=[white,normal_texture]
	var data:=PackedByteArray();data.resize(64)
	data.encode_u32(0,land_size.x);data.encode_u32(4,land_size.y);data.encode_u32(8,64)
	var code:=tile_index|(rotation<<14)
	var tiles_data:=PackedInt32Array();tiles_data.resize(land_size.x*land_size.y)
	tiles_data.fill(((tile_index+1)%(atlas_axis*atlas_axis))|(ground_type<<16))
	var tile_id:=land_cell.y*land_size.x+land_cell.x
	tiles_data[tile_id]=code|(ground_type<<16)|((1<<24) if mode==3 else 0)
	data.append_array(tiles_data.to_byte_array());data.encode_u32(12,data.size())
	data.append_array(PackedInt32Array([tile_id+1,tile_id+1]).to_byte_array())
	data.encode_float(16,float(atlas_axis));data.encode_float(20,atlas_padding);data.encode_float(24,1.0/(atlas_axis*64));data.encode_float(28,1)
	data.encode_u32(32,2 if use_normal else 0);data.encode_u32(44,1)
	var tiles:=Image.create(1,1,false,Image.FORMAT_RGBAF);tiles.set_pixel(0,0,Color(code,ground_type,0,0));tile_texture=ImageTexture.create_from_image(tiles)
	if mode in [1,2]:
		var rows:=PackedColorArray([Color(1,2,5|(2<<12)|(0<<16),1|(2<<6))])
		if mode==2:rows[0].b=float(5|(2<<12)|(0<<16)|(15<<20))
		data.encode_u32(56,data.size());data.append_array(rows.to_byte_array())
		if mode==2:
			var extra:=PackedColorArray([Color(1|(2<<6)|(3<<12)|(4<<18),228,3|(3<<15),4|(10<<15))])
			data.encode_u32(60,data.size());data.append_array(extra.to_byte_array());rows.append_array(extra)
		transition_texture=ImageTexture.create_from_image(Image.create_from_data(1,rows.size(),false,Image.FORMAT_RGBAF,rows.to_byte_array()))
	if mode==3:
		data.encode_u32(40,data.size());data.encode_u32(48,3);data.encode_u32(52,3)
		data.resize(data.size()+12)
		var eligible:=Image.create(1,1,false,Image.FORMAT_R8);eligible.fill(Color.WHITE);cliff_texture=ImageTexture.create_from_image(eligible)
		var guards:=Image.create(3,3,false,Image.FORMAT_R8);guard_texture=ImageTexture.create_from_image(guards)
	device.terrain.data=data;device.terrain.atlas=atlas
	geometries=[{"offset":0,"count":6,"opaque":true,"standard":true,"terrain":true}]
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7}]
	RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements));return await device.prepared

func comparison(label: String) -> void:
	check(await build_land(),"build terrain material: "+label);await render_many(2)
	var inv:=camera.get_camera_projection().inverse()
	var params:=PackedFloat32Array([inv.x.x,inv.y.y,2*inv.x.x/size.x,2*inv.y.y/size.y,offset.x,offset.y,offset.z,0]).to_byte_array()
	RenderingServer.call_on_render_thread(reference_render.bind(reference_code(),params));await filtered
	check(reference_image!=null,"compile independent raster sampler: "+label)
	if reference_image==null:return
	var traced:=device.shadow1.get_image();var error:=0.0;var peak:=0.0;var count:=0
	for y in range(size.y/3,2*size.y/3):
		for x in range(size.x/3,2*size.x/3):
			var a:=traced.get_pixel(x,y);var b:=reference_image.get_pixel(x,y)
			var delta:=maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
			error+=delta;peak=maxf(peak,delta);count+=1
	report[label]={"mean_error":error/count,"peak_error":peak}
	check(error/count<0.006 and peak<0.025,"traced colour matches raster sampler: "+label+" "+str(report[label]))
	reference_image=null

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified terrain material device")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4;camera.current=true
	size=fixture_size;camera.position=Vector3(0,0,72);sun_energy=1;sky_energy=0;bounces=1
	for turn in 4:rotation=turn;await comparison("rotation-"+str(turn))
	rotation=0
	# Exercise tile row decoding beyond tile zero, including a non-power-of-two
	# atlas, against the unchanged raster GLSL rather than a second HLSL formula.
	for row in [[2,3],[3,8],[8,63]]:
		atlas_axis=row[0];tile_index=row[1];await comparison("atlas-%s-tile-%s"%[atlas_axis,tile_index])
	# Distinct surrounding tiles catch a wrong row/column rather than merely
	# validating an address formula. Include the integer-division fallback.
	atlas_axis=2;tile_index=0
	for grid: Vector2i in [Vector2i(16,3),Vector2i(17,3),Vector2i(256,256)]:
		land_size=grid;land_cell=grid-Vector2i.ONE
		await comparison("land-grid-%s-last-cell"%grid)
	land_size=Vector2i.ONE;land_cell=Vector2i.ZERO
	atlas_axis=2;tile_index=0;size=Vector2i(40,24)
	await comparison("coarse-padded-mip")
	atlas_padding=0.0;await comparison("coarse-unpadded-mip")
	atlas_padding=0.125;size=fixture_size
	for selected in [1,2,3]:
		mode=selected;var label: String=["detailed","pair","junction","cliff"][mode]
		await comparison(label)
		size=Vector2i(40,24);await comparison(label+"-coarse-mip");size=fixture_size
	offset=Vector3(17,5,0);camera.position=offset+Vector3(0,0,72);mode=0;await comparison("shifted-authored-tile")
	# Constant normals isolate real normal-texture response from colour relief.
	camera.position=offset+Vector3(0,0,3)
	check(await build_land(),"build colour-relief control without normal detail");await render_many(2)
	var base_normal:=mean(device.guide)
	use_normal=true
	check(await build_land(),"build normal-detail terrain");await render_many(2)
	var normal:=mean(device.guide);var direction:=Vector3(normal.r,normal.g,normal.b)
	check(direction.is_finite() and direction.z>0.9 and absf(direction.x)>0.01,"normal texture changes the traced surface and stays outward")
	check(direction.distance_to(Vector3(base_normal.r,base_normal.g,base_normal.b))>0.02,"normal texture adds detail beyond the colour-derived relief")
	var rough:=int(mean(device.shadow1).a)&63
	check(absf(rough/63.0-0.84)<0.02,"rock type controls traced roughness")
	ground_type=0;check(await build_land(),"build grass material");await render_many(2)
	check(absf((int(mean(device.shadow1).a)&63)/63.0-0.96)<0.02,"grass keeps a separate roughness")
	# A near vertical face must receive relief from its projected rock texture,
	# even with the procedural normal texture disabled. Check every sampled
	# normal as well as a visible change; this catches flipped/grazing normals.
	mode=3;use_normal=false;ground_type=2
	check(await build_land(),"build near cliff with projected painted relief");await render_many(2)
	var cliff_normals:=device.guide.get_image();var valid:=true;var tilted:=0;var samples:=0
	for y in range(size.y/3,2*size.y/3):
		for x in range(size.x/3,2*size.x/3):
			var pixel:=cliff_normals.get_pixel(x,y);var n:=Vector3(pixel.r,pixel.g,pixel.b)
			valid=valid and n.is_finite() and n.z>0.8 and absf(n.length()-1.0)<0.003
			if absf(n.x)>0.01:tilted+=1
			samples+=1
	check(valid,"near cliff relief keeps finite outward unit normals")
	check(tilted>samples/2,"projected rock texture perturbs normals without the noise normal texture")
	report["cliff-relief"]={"samples":samples,"tilted":tilted,"valid":valid}
	RenderingServer.call_on_render_thread(device.dispose);await frames(6)
	check(device.terrain.atlas==null,"disposing PT releases its retained raster atlas")
	camera.queue_free()
	FileAccess.open(out.path_join("path-terrain.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"results":report},"\t"))
	finish()
