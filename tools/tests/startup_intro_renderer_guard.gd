extends Node
## Start the real entry point in a fresh child profile. Interrupt it when it
## reaches the movie stage, the exact stage of the supplied D3D12 device hang.
## A durable fallback must already exist before that stage is entered.
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func _ready()->void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	var root:=ProjectSettings.globalize_path("user://startup-child")
	var user:=root.path_join("data/godot/app_userdata/Cursed Lands")
	DirAccess.make_dir_recursive_absolute(user)
	var settings:=ConfigFile.new()
	for option in {"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,"auto_graphics":0,"display_mode":0,"net_upnp":0,"net_lan":0,"net_directory":0}:
		settings.set_value("options",option,1 if option=="show_fps" else 0)
	check(settings.save(user.path_join("settings.cfg"))==OK,"isolated movie-test profile created")
	var log_path:=root.path_join("startup.log")
	var args:=PackedStringArray(["--render-thread","safe","--display-driver","x11","--audio-driver","Dummy",
		"--max-fps","30","--windowed","--resolution","960x540","--rendering-method","forward_plus",
		"--rendering-driver","vulkan","--log-file",log_path])
	if OS.has_feature("editor"):args.append_array(["--path",ProjectSettings.globalize_path("res://")])
	args.append_array(["--","--ei-path="+GameData.root,"--windows-renderer-option","--vulkan-recovery"])
	var saved:={}
	for kind:String in ["DATA","CONFIG","CACHE"]:
		var key:="XDG_"+kind+"_HOME"
		saved[key]=OS.get_environment(key) if OS.has_environment(key) else null
		OS.set_environment(key,root.path_join(kind.to_lower()))
	var pid:=OS.create_process(OS.get_executable_path(),args)
	for key:String in saved:
		if saved[key]==null:OS.unset_environment(key)
		else:OS.set_environment(key,saved[key])
	check(pid>0,"ordinary graphical startup launched")
	var deadline:=Time.get_ticks_msec()+60000
	var log_text:=""
	while pid>0 and OS.is_process_running(pid) and Time.get_ticks_msec()<deadline:
		if FileAccess.file_exists(log_path):log_text=FileAccess.get_file_as_string(log_path)
		if log_text.contains("startup: intro movies"):break
		await get_tree().process_frame
	# This child and its disposable profile belong exclusively to the test.
	if pid>0 and OS.is_process_running(pid):OS.kill(pid)
	check(log_text.contains("startup: intro movies"),"real startup reaches movie presentation")
	var guard:=log_text.find("renderer detection: testing vulkan")
	var intro:=log_text.find("startup: intro movies")
	check(guard>=0 and guard<intro,"renderer fallback is armed before intro GPU work")
	var trial:=ConfigFile.new()
	check(trial.load(user.path_join("renderer_trial.cfg"))==OK and trial.get_value("trial","state","")=="running"
		and trial.get_value("trial","driver","")=="vulkan","interrupted movie leaves an identifiable renderer trial")
	var next:=ConfigFile.new()
	check(next.load(user.path_join("renderer.cfg"))==OK and next.get_value("rendering","rendering_device/driver.windows","")!="vulkan",
		"next launch does not repeat the interrupted graphics API")
	print("STARTUP_INTRO_RENDERER_GUARD ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
