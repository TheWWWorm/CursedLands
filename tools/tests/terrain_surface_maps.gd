extends Node
## Derived terrain surface maps on the renderer's own GPU: painted slope
## without broad painted shading, per-type roughness, loose-sand weight and
## padded-slot isolation. The production land functions then rotate map
## slope into the same local axes as painted-brightness relief for all four
## authored tile rotations.
var checks:=0
var failures:=0
var _readback: Array[Image]=[]
signal read_done

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)

func frames(count:int)->void:
	for i in count:await get_tree().process_frame

func srgb(value:float)->float:
	return value/12.92 if value<=0.04045 else pow((value+0.055)/1.055,2.4)

## Original 128x128 atlases of four 64-texel tiles; rows count from the bottom.
func tile_origin(tile:int)->Vector2i:
	return Vector2i((tile%2)*64,(1-tile/2)*64)

func source_layers()->Array[Image]:
	var a:=Image.create(128,128,false,Image.FORMAT_RGBA8)
	# Tile 0: grey with a narrow vertical and a narrow horizontal bright line.
	var o:=tile_origin(0);a.fill_rect(Rect2i(o,Vector2i(64,64)),Color(0.4,0.4,0.4))
	a.fill_rect(Rect2i(o+Vector2i(32,0),Vector2i(2,64)),Color(0.9,0.9,0.9))
	a.fill_rect(Rect2i(o+Vector2i(0,20),Vector2i(64,2)),Color(0.9,0.9,0.9))
	# Tile 1: broad painted shading only, a linear ramp across the tile.
	o=tile_origin(1)
	for x in 64:a.fill_rect(Rect2i(o+Vector2i(x,0),Vector2i(1,64)),Color.from_hsv(0,0,0.1+0.8*x/63.0))
	# Tiles 2 and 3: flat grey beside unrelated flat white.
	a.fill_rect(Rect2i(tile_origin(2),Vector2i(64,64)),Color(0.5,0.5,0.5))
	a.fill_rect(Rect2i(tile_origin(3),Vector2i(64,64)),Color.WHITE)
	# Layer 1: an asymmetric bright blob, for the rotation reference.
	var b:=Image.create(128,128,false,Image.FORMAT_RGBA8);b.fill(Color(0.45,0.45,0.45))
	o=tile_origin(0)
	for y in 64:
		for x in 64:
			var d:=Vector2(x-24,(y-38)*1.7).length()
			var v:=0.45+0.4*exp(-d*d/40.0)+0.25*exp(-pow(x-44,2)/6.0)*float(y<30)
			b.set_pixel(o.x+x,o.y+y,Color(v,v,v))
	return [a,b]

func read_layers(rid:RID,count:int,size:int)->void:
	var rd:=RenderingServer.get_rendering_device()
	_readback.clear()
	for layer in count:
		var bytes:=rd.texture_get_data(rid,layer)
		_readback.append(Image.create_from_data(size,size,false,Image.FORMAT_RGBA8,bytes.slice(0,size*size*4)))
	read_done.emit.call_deferred()

## Padded pixel of an in-tile texel (x right, y down in the stored image).
func padded(tile:int,x:int,y:int)->Vector2i:
	var o:=tile_origin(tile)/64
	return Vector2i(o.x*80+8+x,o.y*80+8+y)

func _ready()->void:
	GameData.options.merge({"gfx_terrain":1,"gfx_materials":1,"auto_graphics":0,"confine_mouse":0,
		"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0},true)
	RenderingServer.set_render_loop_enabled(true)
	await frames(3)
	check(TerrainSurfaceMaps.supported(),"Forward+ supplies the compute device for derived maps")
	var padded_images: Array[Image]=[]
	for image in source_layers():
		var p:=EITerrain.padded_atlas(image,64,8);p.generate_mipmaps();padded_images.append(p)
	var atlas:=Texture2DArray.new();atlas.create_from_images(padded_images)
	# Layer 0: stone, sand, ice, grass. Layer 1: sand everywhere.
	var types:=PackedInt32Array([2,3,10,0,3,3,3,3])
	var started:=Time.get_ticks_usec()
	var maps:=TerrainSurfaceMaps.create(atlas,types,2,80)
	print("TERRAIN_SURFACE_CREATE_MS ",(Time.get_ticks_usec()-started)/1000.0)
	check(maps!=null,"derived surface array is created from the installed atlas")
	if maps==null:return finish()
	check(maps.get_layers()==2 and maps.get_width()==160 and maps.get_height()==160,"surface array keeps the padded atlas layout")
	check(maps.has_mipmaps(),"surface array carries a full mip chain")
	RenderingServer.call_on_render_thread(read_layers.bind(maps.texture_rd_rid,2,160));await read_done
	var m:=_readback[0]
	m.save_png("user://terrain-surface-layer0.png")
	# Narrow painted features: slope points up toward the bright line.
	var left:=m.get_pixelv(padded(0,31,48));var right:=m.get_pixelv(padded(0,34,48))
	check(left.r>0.56 and right.r<0.44,"vertical ridge slopes rise toward it along X: %.3f %.3f"%[left.r,right.r])
	check(absf(left.g-0.5)<0.02 and absf(right.g-0.5)<0.02,"vertical ridge has no Y slope")
	var above:=m.get_pixelv(padded(0,10,19));var below:=m.get_pixelv(padded(0,10,22))
	check(above.g>0.56 and below.g<0.44,"horizontal ridge slopes follow stored image rows: %.3f %.3f"%[above.g,below.g])
	# Broad painted shading is removed. Brightness-only relief would tilt it.
	var ramp:=m.get_pixelv(padded(1,32,32))
	var lum:=func(x:float)->float:return sqrt(srgb(0.1+0.8*x/63.0))
	var legacy:float=0.5+(lum.call(33.5)-lum.call(30.5))/1.2
	check(legacy>0.515,"brightness-only relief would tilt the shaded ramp: %.3f"%legacy)
	check(absf(ramp.r-0.5)<0.008 and absf(ramp.g-0.5)<0.008,"broad painted shading is not turned into relief: %.3f %.3f"%[ramp.r,ramp.g])
	# Per-type roughness and sand weight.
	var flat_stone:=m.get_pixelv(padded(0,10,48));var crest:=m.get_pixelv(padded(0,32,48))
	check(absf(flat_stone.b-0.84)<0.04 and crest.b<flat_stone.b-0.02,"stone roughness 0.84 with smoother crests: %.3f %.3f"%[flat_stone.b,crest.b])
	check(absf(ramp.b-0.98)<0.03 and ramp.a>0.99,"loose sand is matte and flagged: %.3f %.3f"%[ramp.b,ramp.a])
	var ice:=m.get_pixelv(padded(2,32,32));var grass:=m.get_pixelv(padded(3,32,32))
	check(absf(ice.b-0.25)<0.03 and ice.a<0.01,"ice keeps its smooth traced roughness: %.3f"%ice.b)
	check(absf(grass.b-0.96)<0.03 and grass.a<0.01,"grass roughness and no sand flag: %.3f"%grass.b)
	# Padded slots are isolated, including the gutter and coarse shading taps.
	# Tile 2 is the top-left padded slot; tile 3 (white) is its neighbour.
	var leak:=0.0
	for y in range(0,80):
		for x in range(0,80):
			var c:=m.get_pixel(x,y);leak=maxf(leak,maxf(absf(c.r-0.5),absf(c.g-0.5)))
	check(leak<0.01,"flat slot beside a white slot has no slope anywhere, gutter included: %.3f"%leak)
	await rotation_reference(atlas,maps)
	variants()
	GameData.options.gfx_materials=0
	check(not TerrainSurfaceMaps.requested(),"Surface materials off keeps the established relief")
	GameData.options.gfx_materials=1;GameData.options.gfx_terrain=0
	check(not TerrainSurfaceMaps.requested(),"original terrain needs no derived maps")
	finish()

## Cliff, transition and caustic land variants keep the derived-map hooks and
## compile: projected wall rock fades the ground tile's map relief and
## roughness, and transitions blend the map only over owned tiles.
func variants()->void:
	const Cliff=preload("res://src/game/fx/terrain_cliff_shader.gd")
	const Transition=preload("res://src/game/fx/terrain_transition_shader.gd")
	var base:=EITerrain.TERRAIN_SHADER
	var cliff:=Cliff.source(base)
	check(cliff.contains("coverage * (1.0-cliff_planes.y)"),"projected cliff rock fades the derived roughness")
	check(cliff.contains("painted_relief * fade * (1.0-cliff_planes.y)"),"projected cliff rock fades the derived relief")
	var pair:=Transition.source(Cliff.source(EITerrain.WaterCaustics.source(base)))
	var junction:=Transition.source(cliff,true)
	for code: String in [pair,junction]:
		check(code.contains("#define EI_TERRAIN_TRANSITIONS") and code.contains("float surface_owned(") \
			and code.contains("surface = ground_surface("),"transition land blends derived maps by tile ownership")
	var shaders:={"land":base,"cliff land":cliff,"caustic cliff transitions":pair,"cliff junctions":junction,
		"baked cliff land":cliff.replace("shader_type spatial;","shader_type spatial;\n#define EI_BAKED_TERRAIN")}
	for label: String in shaders:
		var shader:=Gfx.make_shader(shaders[label],true,true)
		var names:=shader.get_shader_uniform_list().map(func(u:Dictionary)->String:return u.name)
		check(names.has("surface_atlases") and names.has("surface_maps") and names.has("surface_tuning"),label+" compiles with the derived-map uniforms")
		check(RenderingServer.shader_get_parameter_default(shader.get_rid(),&"surface_tuning")==TerrainSurfaceMaps.tuning,
			label+" defaults to the TerrainSurfaceMaps strength")
	# The chosen strength: stronger relief, deeper/longer ripples, more
	# roughness contrast than the first, barely visible pass.
	check(TerrainSurfaceMaps.tuning==Vector4(1.6,2.5,0.25,2.0),"derived maps use the selected medium strength")
	check(base.contains("surface.xy * surface_tuning.x") and base.contains("(surface.z - base_rough) * surface_tuning.w") \
		and base.contains("surface_tuning.y * fade"),"raster relief, ripples and roughness follow the strength")

## The production TILE_FUNCTIONS and SURFACE_FUNCTIONS, compiled as compute:
## painted-brightness finite differences (ground_sample) and the derived map
## (ground_surface) must agree in direction for every authored rotation.
func rotation_reference(atlas:Texture2DArray,maps:TextureLayered)->void:
	var code:="""#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(rgba32f,set=0,binding=0) uniform writeonly image2D result_image;
layout(set=0,binding=1) uniform sampler2DArray atlases;
layout(set=0,binding=2) uniform sampler2D terrain_tiles;
layout(set=0,binding=3) uniform sampler2DArray surface_atlases;
const float tiles_per_axis=2.0;
const float atlas_padding=0.125;
const float source_texel=1.0/128.0;
const bool blend_edges=true;
"""+GroundSurfaceShader.TILE_FUNCTIONS+GroundSurfaceShader.SURFACE_FUNCTIONS+"""
float ground_height(vec3 colour) { return sqrt(max(dot(colour, vec3(0.2126, 0.7152, 0.0722)), 0.0)); }
void main() {
	ivec2 at=ivec2(gl_GlobalInvocationID.xy);
	if(any(greaterThanEqual(at,imageSize(result_image))))return;
	ivec2 cell=ivec2(at.y/16,0);
	vec2 p=vec2(0.2)+vec2(at.x,at.y%16)/15.0*0.6;
	vec2 dx=vec2(1.0/4096.0,0.0),dy=vec2(0.0,1.0/4096.0);
	float border=8.0*source_texel*tiles_per_axis;
	vec2 step_uv=vec2(source_texel*tiles_per_axis*1.5/(1.0-2.0*border),0.0);
	vec4 traits;
	vec2 slope=vec2(ground_height(ground_sample(cell,p+step_uv,dx,dy,traits))-ground_height(ground_sample(cell,p-step_uv,dx,dy,traits)),
		ground_height(ground_sample(cell,p+step_uv.yx,dx,dy,traits))-ground_height(ground_sample(cell,p-step_uv.yx,dx,dy,traits)));
	float coverage;
	vec4 surface=ground_surface(cell,p,dx,dy,coverage);
	imageStore(result_image,at,vec4(slope,surface.xy));
}
"""
	var job:={"code":code,"atlas":atlas.get_rid(),"maps":maps.get_rid(),"image":null,"error":""}
	RenderingServer.call_on_render_thread(_reference.bind(job));await read_done
	check(job.error=="","production surface functions compile as GLSL: "+str(job.error))
	if job.image==null:return
	# Negative control: the forward instead of the inverse quarter turn.
	var turned:=code.replace("tile_turn(vec2(slope.x, -slope.y), (4 - rotation) % 4)","tile_turn(vec2(slope.x, -slope.y), rotation)")
	check(turned!=code,"negative control replaces the production inverse rotation")
	var control:={"code":turned,"atlas":atlas.get_rid(),"maps":maps.get_rid(),"image":null,"error":""}
	RenderingServer.call_on_render_thread(_reference.bind(control));await read_done
	if control.image!=null:
		var wrong:Array[float]=[]
		for rotation in [1,3]:wrong.append(correlation(control.image,rotation)[0])
		check(wrong.max()<0.3,"a wrong inverse rotation is detected: %s"%str(wrong))
	var image:Image=job.image
	for rotation in 4:
		var result:=correlation(image,rotation)
		print("TERRAIN_SURFACE_ROTATION ",rotation," correlation ",result[0]," quarter ",result[1]," energy ",result[2])
		check(result[0]>0.7,"map slope follows painted relief at rotation %d: %.3f"%[rotation,result[0]])
		check(absf(result[1])<0.5,"a quarter-turned map would not match at rotation %d: %.3f"%[rotation,result[1]])
		check(result[2]>0.5 and result[2]<2.0,"map relief keeps the painted relief scale at rotation %d: %.3f"%[rotation,result[2]])

## [correlation, quarter-turn correlation, map/painted energy ratio]
func correlation(image:Image,rotation:int)->Array[float]:
	var dot:=0.0;var ll:=0.0;var mm:=0.0;var wrong:=0.0
	for y in range(rotation*16,rotation*16+16):
		for x in 16:
			var c:=image.get_pixel(x,y);var legacy:=Vector2(c.r,c.g);var map:=Vector2(c.b,c.a)
			dot+=legacy.dot(map);ll+=legacy.length_squared();mm+=map.length_squared()
			wrong+=legacy.dot(map.rotated(PI*0.5))
	var norm:=sqrt(maxf(ll*mm,1e-12))
	return [dot/norm,wrong/norm,sqrt(mm/maxf(ll,1e-12))]

func _reference(job:Dictionary)->void:
	var rd:=RenderingServer.get_rendering_device()
	var source:=RDShaderSource.new();source.source_compute=job.code
	var spirv:=rd.shader_compile_spirv_from_source(source)
	job.error=spirv.compile_error_compute
	if job.error!="":read_done.emit.call_deferred();return
	var shader:=rd.shader_create_from_spirv(spirv);var pipeline:=rd.compute_pipeline_create(shader)
	var fmt:=RDTextureFormat.new();fmt.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.width=16;fmt.height=64;fmt.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var result:=rd.texture_create(fmt,RDTextureView.new())
	# Tile 0 of layer 1 in each quarter turn; type 3 (sand).
	var tiles:=PackedFloat32Array()
	for rotation in 4:tiles.append_array([float((rotation<<14)|(1<<6)|0),3.0,0.0,0.0])
	var tf:=RDTextureFormat.new();tf.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT;tf.width=4;tf.height=1
	tf.usage_bits=RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var tile_texture:=rd.texture_create(tf,RDTextureView.new(),[tiles.to_byte_array()])
	var state:=RDSamplerState.new();state.min_filter=RenderingDevice.SAMPLER_FILTER_LINEAR;state.mag_filter=RenderingDevice.SAMPLER_FILTER_LINEAR
	state.mip_filter=RenderingDevice.SAMPLER_FILTER_LINEAR
	var linear:=rd.sampler_create(state);var nearest:=rd.sampler_create(RDSamplerState.new())
	var uniforms:Array[RDUniform]=[]
	var image:=RDUniform.new();image.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;image.binding=0;image.add_id(result);uniforms.append(image)
	# The land material samples the colour atlas as source_color (linear).
	for entry in [[1,linear,RenderingServer.texture_get_rd_texture(job.atlas,true)],[2,nearest,tile_texture],[3,linear,RenderingServer.texture_get_rd_texture(job.maps,false)]]:
		var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE;u.binding=entry[0]
		u.add_id(entry[1]);u.add_id(entry[2]);uniforms.append(u)
	var set:=rd.uniform_set_create(uniforms,shader,0)
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set,0)
	rd.compute_list_dispatch(list,2,8,1);rd.compute_list_end()
	job.image=Image.create_from_data(16,64,false,Image.FORMAT_RGBAF,rd.texture_get_data(result,0))
	# Freeing the shader also frees its dependent pipeline.
	for rid:RID in [set,result,tile_texture,linear,nearest,shader]:
		if rid.is_valid():rd.free_rid(rid)
	read_done.emit.call_deferred()

func finish()->void:
	TexUpscale.shutdown()
	print("TERRAIN_SURFACE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures>0 else 0)
