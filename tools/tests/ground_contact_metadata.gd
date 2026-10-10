extends Node
## Read exact GPU float bits through RGB bytes; generic GLES array readback
## clamps floats into RGBA8 and cannot establish data-texture equivalence.
var checks := 0
var failures := 0
const WIDTH := 2048
var mismatches := []
var cases := []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)
func frames(count: int) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
func decode(image: Image, row: int) -> PackedByteArray:
	var data := image.get_region(Rect2i(0,row,WIDTH,1)).get_data()
	var result := PackedByteArray()
	for i in WIDTH/2:
		for offset in [0,1,2,4]: result.append(data[i*8+offset])
	return result
func probe(dimensions: Vector2i) -> void:
	RenderingServer.set_render_loop_enabled(true)
	var view := SubViewport.new(); view.size = Vector2i(WIDTH,8)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
	var bytes := PackedByteArray(); bytes.resize(256*4)
	for i in 256:
		for c in 4: bytes[4*i+c] = (i+c*61)%256
	var light := Image.create_from_data(256,1,false,Image.FORMAT_RGBA8,bytes)
	var normal := Image.create(256,1,false,Image.FORMAT_RGBAF)
	for i in 256:
		var n := Vector3(sin(float(i)*1.735),cos(float(i)*0.345),sin(float(i)*2.19+0.31)).normalized()
		normal.set_pixel(i,0,Color(n.x,n.y,n.z,1.0))
	var cells := Image.create(dimensions.x,dimensions.y,false,Image.FORMAT_RGBAF)
	for y in dimensions.y:
		for x in dimensions.x: cells.set_pixel(x,y,Color(-10000.0+(y*dimensions.x+x)*31.75,x%16,y%16,(x+y)%64))
	var cover := Image.create(1,1,false,Image.FORMAT_RF); cover.fill(Color(-10000,0,0,0))
	var uv := Image.create(256,1,false,Image.FORMAT_RGF)
	for i in 256:
		# Include pixel centres, both sides of exact nearest-filter edges,
		# map borders and clamping outside the map's normalized rectangle.
		var offset: float = [0.5,0.0,0.0000001,-0.0000001][i%4]
		uv.set_pixel(i,0,Color((float(i%21)-2+offset)/float(dimensions.x),(float(i%13)-2+offset)/float(dimensions.y),0,0))
	var pool := GroundContactData.new()
	pool.build({"query_normals":normal,"query_light_inputs":light,"terrain_cells":cells})
	var original := """shader_type spatial;
render_mode unshaded,blend_disabled;
#define EI_GROUND_CONTACT
uniform sampler2D ref_light : filter_nearest,repeat_disable;
uniform sampler2D ref_normal : filter_nearest,repeat_disable;
uniform sampler2D ref_cells : filter_nearest,repeat_disable;
uniform sampler2D ref_cover : filter_nearest,repeat_disable;
uniform sampler2D probe_uv : filter_nearest,repeat_disable;
uniform sampler2D query_light_inputs : filter_nearest,repeat_disable;
uniform sampler2D query_normals : filter_nearest,repeat_disable;
uniform sampler2D terrain_cells : filter_nearest,repeat_disable;
uniform sampler2D rain_cover : filter_nearest,repeat_disable;
vec2 soft_sample(vec2 uv) {
	return vec2(0.0);
}
void fragment() {
	ivec2 p=ivec2(FRAGCOORD.xy);int x=p.x/8;int component=(p.x/2)%4;int half_word=p.x%2;
	vec2 uv=texelFetch(probe_uv,ivec2(x,0),0).rg;
	vec4 a=texelFetch(ref_light,ivec2(x,0),0);
	if(p.y==1){a=texelFetch(query_light_inputs,ivec2(x,0),0);}
	if(p.y==2){a=texelFetch(ref_normal,ivec2(x,0),0);}
	if(p.y==3){a=texelFetch(query_normals,ivec2(x,0),0);}
	if(p.y==4){a=textureLod(ref_cells,uv,0.0);}
	if(p.y==5){a=textureLod(terrain_cells,uv,0.0);}
	if(p.y==6){a=vec4(textureLod(ref_cover,uv,0.0).r);}
	if(p.y==7){a=vec4(textureLod(rain_cover,uv,0.0).r);}
	uint bits=floatBitsToUint(a[component]);
	if(half_word==0){COLOR=vec4(vec3(float(bits&255u),float((bits>>8u)&255u),float((bits>>16u)&255u))/255.0,1.0);}
	else{COLOR=vec4(float((bits>>24u)&255u)/255.0,0.0,1.0,1.0);}
}
"""
	var terrain := EITerrain.new(); terrain.sectors_x=dimensions.x; terrain.sectors_y=dimensions.y
	original = GroundContactData.specialize(original,terrain); terrain.free()
	var shader := Shader.new()
	shader.code = GroundContactData.source(original).replace("shader_type spatial;","shader_type canvas_item;")
	var material := ShaderMaterial.new(); material.shader = shader
	for entry in [["ref_light",light],["ref_normal",normal],["ref_cells",cells],["ref_cover",cover],["probe_uv",uv],["rain_cover",cover]]:
		material.set_shader_parameter(entry[0],ImageTexture.create_from_image(entry[1]))
	pool.bind(material)
	var rect := ColorRect.new(); rect.size=Vector2(WIDTH,8); rect.material=material; view.add_child(rect)
	await frames(24)
	var image := view.get_texture().get_image(); image.convert(Image.FORMAT_RGBA8)
	for row in [0,2,4,6]:
		var a := decode(image,row); var b := decode(image,row+1)
		check(a==b,"GPU float bits match field "+str(row/2))
		for i in WIDTH/2:
			if a.slice(i*4,i*4+4)!=b.slice(i*4,i*4+4) and mismatches.size()<12:
				mismatches.append({"dimensions":str(dimensions),"field":row/2,"sample":i/4,"component":i%4,"reference":Array(a.slice(i*4,i*4+4)),"candidate":Array(b.slice(i*4,i*4+4))})
	var expanded := light.duplicate(); expanded.convert(Image.FORMAT_RGBAF)
	check(decode(image,0)==expanded.get_data(),"reference UNORM bits equal CPU expansion")
	check(decode(image,2)==normal.get_data(),"reference normal bits equal CPU source")
	image.save_png("user://contact-sampler-budget.png")
	# Rebuild the same shared resource from CPU snapshots, as a Natural-mode
	# change does. Integer fields cross array pages without changing bits.
	var old_rid := pool.texture.get_rid()
	var old_layers := pool.texture.get_layers()
	var changed := cells.duplicate() as Image; changed.fill(Color(7.25,7.25,7.25,7.25))
	var cliff := Image.create(16,17,false,Image.FORMAT_R8); cliff.fill(Color(1,0,0,1))
	pool.build({"query_normals":normal,"query_light_inputs":light,"terrain_cells":changed,"cliff_tiles":cliff}); pool.bind(material)
	await frames(8)
	var updated := view.get_texture().get_image(); updated.convert(Image.FORMAT_RGBA8)
	check(pool.texture.get_rid()==old_rid,"metadata rebuild preserves shared RID")
	check(pool.texture.get_layers()>old_layers,"optional metadata resizes the shared GPU array")
	var expected := PackedFloat32Array(); expected.resize(1024); expected.fill(7.25)
	check(decode(updated,5)==expected.to_byte_array(),"changed cells preserve all float bits after rebuild")
	for row in [1,3,7]: check(decode(updated,row)==decode(image,row),"rebuild preserves other field "+str(row))
	view.free(); await frames(4)
	cases.append({"dimensions":str(dimensions),"power_of_two_pages":original.contains("EI_CONTACT_POWER_OF_TWO_PAGES"),"bytes":pool.bytes})

func _ready() -> void:
	await probe(Vector2i(17,9))
	await probe(Vector2i(16,8))
	var result := {"checks":checks,"failures":failures,"mismatches":mismatches,"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"cases":cases}
	FileAccess.open("user://contact-sampler-budget.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	print("CONTACT_SAMPLER_BUDGET ",JSON.stringify(result)); get_tree().quit(1 if failures else 0)
