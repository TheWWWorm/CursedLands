extends Node
## Allocate > the old 65,536-entry heap, release, and repeat on the main RD.
## Synthetic capacity/reclamation check, not a reproduction of a player save.
const SETS := 2048
const PER_SET := 64
var rows:Array=[]
var failures:Array[String]=[]
var done:=false
var count:=0
var deadline:=0
func _ready():
	process_mode=Node.PROCESS_MODE_ALWAYS
	deadline=Time.get_ticks_msec()+90000
	_run.call_deferred()
func _process(_dt):
	if Time.get_ticks_msec()>deadline:
		printerr("FAIL descriptor test timeout");get_tree().quit(1)
func _allocate():
	var rd:=RenderingServer.get_rendering_device()
	var source:=RDShaderSource.new()
	source.source_compute="""#version 450
layout(local_size_x=1,local_size_y=1,local_size_z=1) in;
layout(set=0,binding=0,rgba8) uniform readonly image2D images[64];
layout(set=1,binding=0,std430) buffer Output { vec4 value; } output_data;
void main() { output_data.value=imageLoad(images[gl_GlobalInvocationID.x%64],ivec2(0)); }
"""
	var spirv:=rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():
		failures.append(spirv.compile_error_compute);done=true;return
	var shader:=rd.shader_create_from_spirv(spirv)
	var format:=RDTextureFormat.new()
	format.width=1;format.height=1
	format.format=RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var texture:=rd.texture_create(format,RDTextureView.new(),[])
	var uniform:=RDUniform.new()
	uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;uniform.binding=0
	for i in PER_SET:uniform.add_id(texture)
	var allocated:Array[RID]=[]
	for i in SETS:
		var set:=rd.uniform_set_create([uniform],shader,0)
		if not set.is_valid():break
		allocated.append(set)
	count=allocated.size()
	for set:RID in allocated:rd.free_rid(set)
	rd.free_rid(texture);rd.free_rid(shader)
	done=true
func _run():
	if RenderingServer.get_current_rendering_driver_name()!="d3d12":
		printerr("FAIL requires the Windows D3D12 renderer");get_tree().quit(2);return
	for cycle in 3:
		done=false;count=0
		RenderingServer.call_on_render_thread(_allocate)
		while not done:await get_tree().process_frame
		rows.append({"cycle":cycle,"sets":count,"descriptors":count*PER_SET})
		if count!=SETS:failures.append("cycle %d allocated %d/%d sets"%[cycle,count,SETS])
		for i in 12:await get_tree().process_frame
	var result:={"capacity":ProjectSettings.get_setting("rendering/rendering_device/d3d12/max_resource_descriptors"),"rows":rows,"failures":failures}
	FileAccess.open("user://descriptor-budget.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("DESCRIPTOR_BUDGET ",JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)
