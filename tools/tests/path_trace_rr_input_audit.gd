extends CompositorEffect
## Runs inside the real viewport's render transaction. Invalid guide sets must
## be rejected before entering the SDK; restore valid inputs before evaluation.
var owner_effect: WeakRef
var results:=[]
signal inspected
func _init() -> void:effect_callback_type=EFFECT_CALLBACK_TYPE_POST_OPAQUE
func _render_callback(kind: int,data: RenderData) -> void:
	if kind!=EFFECT_CALLBACK_TYPE_POST_OPAQUE or not results.is_empty():return
	var effect: Object=owner_effect.get_ref()
	if effect==null or effect._images.size()!=4:return
	var buffers: RenderSceneBuffersRD=data.get_render_scene_buffers()
	var rd:=RenderingServer.get_rendering_device()
	var scene: RenderSceneData=data.get_render_scene_data()
	var ray_projection: Projection=scene.call("get_ray_projection")
	var raster:=scene.get_cam_projection()
	var corrected:=Projection.create_depth_correction(true)*ray_projection
	var aligned:=true
	for i in 4:aligned=aligned and corrected[i].is_equal_approx(raster[i])
	results.append(aligned)
	var images: Array=effect._images
	var format:=RDTextureFormat.new();format.width=1;format.height=1
	format.format=RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var tiny:=rd.texture_create(format,RDTextureView.new())
	results.append(not buffers.call("set_dlss_ray_reconstruction",RID(),images[1],images[2],images[3],false))
	results.append(not buffers.call("set_dlss_ray_reconstruction",tiny,images[1],images[2],images[3],false))
	results.append(not buffers.call("set_dlss_ray_reconstruction",images[0],images[1],images[2],images[0],false))
	results.append(buffers.call("set_dlss_ray_reconstruction",images[0],images[1],images[2],images[3],false))
	rd.free_rid(tiny)
	inspected.emit.call_deferred()
