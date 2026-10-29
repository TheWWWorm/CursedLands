extends "res://tools/tests/path_trace_rr_resources.gd"
## Real GPU images, queued render order, descriptor failure and ownership.
## Stable wrapper identities alone are insufficient: physical RD images and
## RS textures must survive while current AOV bytes continue to change.
const PresentationController = preload("res://src/game/fx/scene_raytrace.gd")
class PresentationPath extends MeasuredPath:
	var fail_set_after:=-1
	var created_sets: Array[RID]=[]
	func _target_set(bindings: Array[RDUniform],shader: RID) -> RID:
		if fail_set_after==0:fail_set_after=-1;return RID()
		if fail_set_after>0:fail_set_after-=1
		var rid:=super._target_set(bindings,shader)
		if rid.is_valid():created_sets.append(rid)
		return rid

var feature_cache:=false
var presentation_state:={}
var presentation_rows:=[]

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var data:=super.frame(history,gi,shadows);data.encode_float(190*4,float(feature_cache));return data

func build_presentation(shared: RefCounted) -> bool:
	device=PresentationPath.new();device.programs=shared
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	return await device.prepared

func handles(target: RefCounted) -> Array:
	var result:=[]
	for texture: Texture2DRD in [target.output,target.guide,target.shadow0,target.shadow1,target.direct_sun,
		target.transmission.colour,target.transmission.guide]:
		result.append([texture.get_instance_id(),texture.get_rid(),texture.texture_rd_rid])
	return result

func public_images(target: RefCounted) -> Array:
	var result: Array=target.published_targets()
	if target.transmission.active:result.append_array(target.transmission._images.slice(0,2))
	return result

func pixels(target: RefCounted) -> Array:
	var result:=[]
	for rid: RID in public_images(target):result.append(target._rd.texture_get_data(rid,0))
	return result

func inspect_handoff(previous: PresentationPath,target: PresentationPath,fail_after: int) -> void:
	var old_handles:=handles(previous);var private_handles:=handles(target)
	var old_pixels:=pixels(previous);var private_pixels:=pixels(target)
	var before_bytes:=previous.live_bytes()+target.live_bytes()
	var allocated:=target.allocations.size();var before_sets:=target.created_sets.size()
	target.fail_set_after=fail_after
	var adopted: bool=target.call("adopt_presentation",previous) if target.has_method("adopt_presentation") else false
	target.fail_set_after=-1
	var staged_sets_clean:=true
	if not adopted:
		for i in range(before_sets,target.created_sets.size()):staged_sets_clean=staged_sets_clean and not target._rd.uniform_set_is_valid(target.created_sets[i])
	presentation_state={"adopted":adopted,"allocated_images":target.allocations.size()-allocated,
		"bytes_unchanged":before_bytes==previous.live_bytes()+target.live_bytes(),"staged_sets_clean":staged_sets_clean,
		"physical_stable":handles(target)==old_handles,"old_got_private":handles(previous)==private_handles,
		"pixels_retained":pixels(target)==old_pixels,"old_unchanged":handles(previous)==old_handles and pixels(previous)==old_pixels,
		"candidate_unchanged":handles(target)==private_handles and pixels(target)==private_pixels,
		"ray_set_valid":target._rd.uniform_set_is_valid(target._set),"trans_set_valid":not target.transmission.active or target._rd.uniform_set_is_valid(target.transmission._set)}
	presentation_rows.append(presentation_state.duplicate());resources_inspected.emit.call_deferred()

func inspect_pair(previous: PresentationPath,target: PresentationPath) -> void:
	var valid:=true;var raw_equal:=true
	for rid: RID in public_images(target):valid=valid and target._rd.texture_is_valid(rid)
	for i in 4:raw_equal=raw_equal and target.ray_targets()[i]==target._history[i]
	presentation_state={"bytes":previous.live_bytes()+target.live_bytes(),"valid":valid,"raw_equal":raw_equal,
		"ready":target.output_ready(),"handles":handles(target),"pixels":pixels(target),"rendered":target.completed_renders,
		"transmission":target.transmission.active,"sharc":target.sharc.active,"rtxdi":target.rtxdi.active}
	resources_inspected.emit.call_deferred()

func attempt(previous: PresentationPath,target: PresentationPath,fail_after:=-1) -> void:
	RenderingServer.call_on_render_thread(inspect_handoff.bind(previous,target,fail_after));await resources_inspected

func controller_fallback(previous: PresentationPath,target: PresentationPath) -> void:
	var owner:=Game.new();var controller:=PresentationController.new(owner)
	Gfx.ensure_globals()
	var shader:=Shader.new();shader.code="""shader_type canvas_item;
render_mode unshaded;
global uniform sampler2D ei_rt_gi : filter_nearest;
uniform sampler2D reference_tex : filter_nearest;
void fragment() {
 vec3 actual=texture(ei_rt_gi,vec2(.5)).rgb;
 vec3 expected=texture(reference_tex,vec2(.5)).rgb;
 COLOR=length(actual-expected)<.001?vec4(0.,1.,0.,1.):vec4(1.,0.,0.,1.);
}"""
	var material:=ShaderMaterial.new();material.shader=shader;material.set_shader_parameter("reference_tex",target.output)
	var probe:=ColorRect.new();probe.material=material;probe.size=Vector2(64,64);add_child(probe)
	# Deliberately distinct complete pictures make a retained old global bind
	# observable; the diagnostic compares GPU samples, not editor-only getters.
	sky_energy=.15;RenderingServer.call_on_render_thread(previous.render.bind(size,frame(false),{"ray_reconstruction":true},0))
	sky_energy=2;await render_many(1,{"ray_reconstruction":true});sky_energy=1
	controller.device=previous;controller._bind_outputs();await frames(4)
	var before:=get_viewport().get_texture().get_image().get_pixel(16,16)
	check(before.r>.9 and before.g<.1,"controller fallback control sees a distinct old global image")
	var old_handles:=handles(previous);var candidate_handles:=handles(target)
	target.fail_set_after=0
	var available:=controller.has_method("_publish_rr_handoff")
	if available:RenderingServer.call_on_render_thread(controller.call.bind("_publish_rr_handoff",target,previous))
	else:controller.device=target;controller._bound=false;controller._bind_outputs()
	await frames(4);target.fail_set_after=-1
	var after:=get_viewport().get_texture().get_image().get_pixel(16,16)
	check(after.g>.9 and after.r<.1,"controller descriptor-failure fallback binds the current complete candidate to a real raster receiver")
	check(handles(previous)==old_handles and handles(target)==candidate_handles and previous.output_ready() and target.output_ready(),
		"controller fallback preserves both independent resource owners")
	controller.device=previous;controller._bound=false;controller._bind_outputs()
	probe.free();controller.free();owner.free();await frames(1)

func exercise(optional: bool) -> void:
	var label:="RR + transmission/SHARC/RTXDI" if optional else "plain RR"
	var shared:=PathDevice.Programs.new();feature_cache=optional;bounces=4 if optional else 2
	var flags:={"ray_reconstruction":true,"transmission":optional,"rtxdi":optional}
	check(await build_presentation(shared),label+": build visible native owner")
	await render_many(2,flags)
	var previous:=device as PresentationPath
	check(previous.output_ready() and (not optional or (previous.transmission.active and previous.sharc.active and previous.rtxdi.active)),label+": requested native passes execute")
	var original_handles:=handles(previous)
	check(await build_presentation(shared),label+": build unpublished replacement")
	var candidate:=device as PresentationPath
	# Cancellation before any private trace cannot touch visible ownership.
	var unpublished_before:=previous.published_targets()
	RenderingServer.call_on_render_thread(func():
		presentation_state={"adopted":candidate.call("adopt_presentation",previous) if candidate.has_method("adopt_presentation") else false}
		candidate.dispose();resources_inspected.emit.call_deferred())
	await resources_inspected
	check(not presentation_state.adopted and previous.published_targets()==unpublished_before and previous.output_ready(),label+": unrendered cancellation leaves active images usable")
	check(await build_presentation(shared),label+": build complete private replacement")
	candidate=device as PresentationPath;await render_many(2,flags)
	await attempt(previous,candidate,0)
	check(not presentation_state.adopted and presentation_state.old_unchanged and presentation_state.candidate_unchanged,label+": ray descriptor failure rolls back both complete pictures")
	check(presentation_state.bytes_unchanged and presentation_state.allocated_images==0 and presentation_state.staged_sets_clean,label+": failed transaction has no image or descriptor leak")
	if optional:
		await attempt(previous,candidate,1)
		check(not presentation_state.adopted and presentation_state.old_unchanged and presentation_state.candidate_unchanged
			and presentation_state.staged_sets_clean,label+": second descriptor failure also rolls back opaque ownership")
	# Real resize and mode transitions must take ordinary publication. A guard
	# cannot transplant a differently sized/filtered image into a live sampler.
	size=Vector2i(173,99);await render_many(1,flags);await attempt(previous,candidate)
	check(not presentation_state.adopted and presentation_state.old_unchanged and presentation_state.candidate_unchanged,label+": different target sizes retain separate valid owners")
	size=Vector2i(160,90);await render_many(1,{"ray_reconstruction":false,"transmission":optional,"rtxdi":optional})
	await attempt(previous,candidate)
	check(not presentation_state.adopted and presentation_state.old_unchanged and presentation_state.candidate_unchanged,label+": filtered reconstruction cannot inherit raw RR presentation")
	await render_many(1,flags)
	if not optional:await controller_fallback(previous,candidate)
	if optional:
		await render_many(1,{"ray_reconstruction":true,"transmission":false,"rtxdi":true});await attempt(previous,candidate)
		check(not presentation_state.adopted and presentation_state.old_unchanged and presentation_state.candidate_unchanged,label+": transmission mode change uses full publication fallback")
		await render_many(1,flags)
	# Queue an ordinary old-owner frame before adoption, then queue the new
	# owner's current frame. RenderingDevice barriers retain that exact order.
	RenderingServer.call_on_render_thread(previous.render.bind(size,frame(false),flags,0))
	await attempt(previous,candidate)
	check(presentation_state.adopted and presentation_state.physical_stable and presentation_state.old_got_private,label+": physical RD images, RS textures and wrappers transfer together")
	check(presentation_state.pixels_retained and presentation_state.bytes_unchanged and presentation_state.allocated_images==0,label+": commit preserves the last complete picture with zero extra image memory or copies")
	check(presentation_state.ray_set_valid and presentation_state.trans_set_valid,label+": all replacement descriptors are valid before commit")
	RenderingServer.call_on_render_thread(inspect_pair.bind(previous,candidate));await resources_inspected
	var retained_pixels: Array=presentation_state.pixels;var renders: int=presentation_state.rendered
	sky_energy=2;await render_many(1,flags);sky_energy=1
	RenderingServer.call_on_render_thread(inspect_pair.bind(previous,candidate));await resources_inspected
	check(presentation_state.valid and presentation_state.raw_equal and presentation_state.ready and presentation_state.rendered==renders+1
		and presentation_state.pixels!=retained_pixels,label+": first visible frame traces fresh radiance and matching current guides")
	check(presentation_state.handles==original_handles,label+": first current frame never replaces a bound physical texture")
	var stable: Array=presentation_state.handles
	RenderingServer.call_on_render_thread(previous.begin_retirement)
	for i in 80:
		RenderingServer.call_on_render_thread(previous.retire_step);await frames(1)
		if previous.retirement_complete():break
	RenderingServer.call_on_render_thread(previous.dispose);await frames(1)
	await render_many(1,flags)
	RenderingServer.call_on_render_thread(inspect_pair.bind(previous,candidate));await resources_inspected
	check(previous.retirement_complete() and presentation_state.valid and presentation_state.ready and presentation_state.raw_equal
		and presentation_state.handles==stable,label+": old staged and repeated disposal cannot invalidate transferred outputs")
	check(not optional or (presentation_state.transmission and presentation_state.sharc and presentation_state.rtxdi),label+": optional passes remain usable after the previous owner retires")
	RenderingServer.call_on_render_thread(candidate.dispose);await frames(1)
	RenderingServer.call_on_render_thread(func():presentation_state={"bytes":previous.live_bytes()+candidate.live_bytes()};resources_inspected.emit.call_deferred())
	await resources_inspected
	check(presentation_state.bytes==0,label+": final teardown frees both generations' tracked images exactly once")
	RenderingServer.call_on_render_thread(shared.dispose);await frames(1)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified native RR presentation device")
	if not PathDevice.supported():finish();return
	size=Vector2i(160,90);sun_energy=0;sky_energy=1;bounces=2
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3;camera.position=Vector3(0,1,.001);camera.look_at(Vector3.ZERO);camera.current=true
	quad(mesh_data,[Vector3(-3,0,-3),Vector3(3,0,-3),Vector3(3,0,3),Vector3(-3,0,3)],Vector3.UP,Vector3.ZERO)
	geometries=[{"offset":0,"count":6,"standard":true,"opaque":true,"surface":Vector3(.3,.2,.75)}]
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7}]
	await exercise(false)
	quad(mesh_data,[Vector3(-3,.5,-3),Vector3(3,.5,-3),Vector3(3,.5,3),Vector3(-3,.5,3)],Vector3.UP,Vector3.ZERO)
	geometries.append({"offset":6,"count":6,"standard":true,"opaque":true,"dielectric":PackedFloat32Array([.2,.1,.02,1.333,1,1,0,0])})
	placements.append({"geometry":1,"transform":Transform3D.IDENTITY,"mask":5})
	await exercise(true)
	FileAccess.open(out.path_join("rr-presentation.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"transactions":presentation_rows},"\t"))
	camera.queue_free();finish()
