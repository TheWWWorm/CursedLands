extends Node
## Runtime evidence for every externally launched PT fixture. This wrapper does
## not change the selected renderer or turn unsupported hardware into a pass.
const Device = preload("res://src/game/fx/path_trace_device.gd")
signal render_thread_recorded
var render_thread_id:=0

func _probe_render_thread() -> void:
	_record_render_thread.call_deferred(OS.get_thread_caller_id())

func _record_render_thread(thread_id: int) -> void:
	render_thread_id=thread_id
	render_thread_recorded.emit()

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	var fixture:="";var out:="";var require_sdk:=false;var requested_thread:="project"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qualification-fixture="):fixture=arg.trim_prefix("--qualification-fixture=")
		elif arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
		elif arg=="--qualification-require-sdk":require_sdk=true
		elif arg.begins_with("--qualification-render-thread="):requested_thread=arg.trim_prefix("--qualification-render-thread=")
	# Measure the actual callback thread instead of inferring it from a setting.
	# Linux production uses a separate renderer; Windows production uses Safe.
	RenderingServer.call_on_render_thread(_probe_render_thread)
	await render_thread_recorded
	var project_thread:=int(ProjectSettings.get_setting_with_override("rendering/driver/threads/thread_model"))
	var expected_separate:=project_thread==2 if requested_thread=="project" else requested_thread=="separate"
	var threads:={"requested":requested_thread,"project_model":project_thread,"main_id":OS.get_main_thread_id(),
		"render_id":render_thread_id,"expected_separate":expected_separate,
		"actual_separate":render_thread_id!=OS.get_main_thread_id()}
	threads["passed"]=render_thread_id!=0 and threads.actual_separate==expected_separate
	var profile:={}
	for key: String in ["confine_mouse","show_fps","volume_sfx","volume_stream","volume_voice"]:
		profile[key]=GameData.option(key)
	var evidence:={"adapter":RenderingServer.get_video_adapter_name(),
		"vendor":RenderingServer.get_video_adapter_vendor(),
		"driver":RenderingServer.get_current_rendering_driver_name(),
		"method":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name(),
		"engine":Engine.get_version_info(),"pid":OS.get_process_id(),
		"user_data":OS.get_user_data_dir(),"profile":profile,"pt_supported":Device.supported(),
		"fsr":FsrGraphics.facts(),"require_sdk":require_sdk,"fixture":fixture,"render_thread":threads}
	var valid: bool=Device.supported() and evidence.method=="forward_plus" and evidence.display!="headless" \
		and profile=={"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0} and threads.passed
	if require_sdk:valid=valid and evidence.fsr.api and evidence.fsr.sr3
	evidence["passed"]=valid
	DirAccess.make_dir_recursive_absolute(out)
	var file:=FileAccess.open(out.path_join("qualification-runtime.json"),FileAccess.WRITE)
	if file==null:
		push_error("PT qualification cannot write runtime evidence");get_tree().quit(1);return
	file.store_string(JSON.stringify(evidence,"\t"));file.close()
	print("PT_QUALIFICATION_RUNTIME ",JSON.stringify(evidence))
	if not valid:
		push_error("PT qualification requires the requested hardware renderer, isolated test settings and explicit SDK support")
		get_tree().quit(1);return
	# The external runner samples actual graphics-process UUIDs every two
	# seconds. Give even a short CPU/topology fixture an observable context;
	# this happens before the selected fixture starts measuring anything.
	await get_tree().create_timer(3.0,true,false,true).timeout
	var script:=load(fixture) as Script
	if script==null or not script.can_instantiate():
		push_error("PT qualification fixture cannot be instantiated: "+fixture);get_tree().quit(1);return
	add_child(script.new())
