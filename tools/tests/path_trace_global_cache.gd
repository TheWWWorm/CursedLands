extends Node
## The shader globals are shared by every controller in a process. A cached
## value must remain correct when another controller writes or retires.
const Controller=preload("res://src/game/fx/scene_raytrace.gd")
var checks:=0
var failures: Array[String]=[]
var viewport: SubViewport
var out:="user://path-global-cache"

func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)

func sample() -> Color:
	for i in 4:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image().get_pixel(8,8)

func publish(controller: Node) -> void:
	controller._set_global(&"ei_pt_active",1.0)
	controller._set_global(&"ei_rt_state",Vector4(1,1,1,42))

func _ready() -> void:run.call_deferred()

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	Gfx.ensure_globals()
	viewport=SubViewport.new();viewport.size=Vector2i(16,16)
	viewport.disable_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var rect:=ColorRect.new();rect.size=Vector2(16,16)
	var shader:=Shader.new()
	shader.code="shader_type canvas_item; global uniform float ei_pt_active; global uniform vec4 ei_rt_state; void fragment(){COLOR=vec4(ei_pt_active,ei_rt_state.x,0.0,1.0);}"
	var material:=ShaderMaterial.new();material.shader=shader;rect.material=material
	viewport.add_child(rect)
	var game:=Game.new()
	var first:=Controller.new(game);var second:=Controller.new(game)
	publish(first)
	var colour:=await sample()
	check(colour.r>.9 and colour.g>.9,"first controller publishes scalar and vector globals")
	second._set_global(&"ei_pt_active",0.0)
	second._set_global(&"ei_rt_state",Vector4.ZERO)
	colour=await sample()
	check(colour.r<.01 and colour.g<.01,"second controller replaces the actual shader globals")
	publish(first);colour=await sample()
	check(colour.r>.9 and colour.g>.9,"first controller restores its unchanged values after another writer")
	second._release();publish(first);colour=await sample()
	check(colour.r>.9 and colour.g>.9,"retiring another controller cannot leave cached PT globals disabled")
	first._release();colour=await sample()
	check(colour.r<.01 and colour.g<.01,"releasing the active controller disables the shader globals")
	publish(first);colour=await sample()
	check(colour.r>.9 and colour.g>.9,"the released controller can publish the same values again")
	viewport.get_texture().get_image().save_png(out.path_join("globals-restored.png"))
	FileAccess.open(out.path_join("globals.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	first.free();second.free();game.free();viewport.queue_free()
	for i in 4:await get_tree().process_frame
	print("PT_GLOBAL_CACHE ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
