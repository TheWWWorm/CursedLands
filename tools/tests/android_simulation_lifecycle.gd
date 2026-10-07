extends Node

var backend:Object
var failures:=0
var checks:=0

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error("Service lifecycle: "+label)

func wait_gone(handle:int)->void:
	var deadline:=Time.get_ticks_msec()+15000
	while backend.is_running(handle) and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	check(not backend.is_running(handle),"service exits")

func _ready()->void:
	backend=Engine.get_singleton("EISimulation")
	check(backend.process_is_alive(OS.get_process_id()),"parent liveness")
	check(not backend.process_is_alive(-1),"reject invalid pid")
	check(backend.start(PackedStringArray(["--help"]))<0,"reject graphical child")
	var args:=PackedStringArray(["--headless","--render-thread","safe","--audio-driver","Dummy","--max-fps","60","--log-file","user://service-lifecycle-child.log","--","--ei-path="+GameData.root,"--tool=res://tools/tests/android_service_counter.gd"])
	var cancelled:int=backend.start(args)
	check(cancelled>0,"start before immediate cancellation")
	backend.stop(cancelled)
	await wait_gone(cancelled)
	var pids:=[]
	for trial in 2:
		if FileAccess.file_exists("user://service-counter.json"):DirAccess.remove_absolute("user://service-counter.json")
		var handle:int=backend.start(args)
		check(handle>0,"restart")
		check(backend.start(args)<0,"reject duplicate")
		var deadline:=Time.get_ticks_msec()+20000
		while not FileAccess.file_exists("user://service-counter.json") and Time.get_ticks_msec()<deadline:await get_tree().process_frame
		if not FileAccess.file_exists("user://service-counter.json"):
			check(false,"child counter starts");backend.stop(handle);await wait_gone(handle);break
		var first:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://service-counter.json"))
		pids.append(first.pid)
		check(first.pid!=OS.get_process_id() and backend.process_is_alive(int(first.pid)),"independent live child")
		backend.stop(cancelled)
		await get_tree().create_timer(0.1).timeout
		check(backend.is_running(handle),"stale cancellation ignored")
		backend.set_active(false)
		await get_tree().create_timer(0.3).timeout
		var paused:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://service-counter.json"))
		await get_tree().create_timer(0.5).timeout
		var held:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://service-counter.json"))
		check(paused.frames==held.frames,"background stops simulation loop")
		backend.set_active(true)
		await get_tree().create_timer(0.5).timeout
		var resumed:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://service-counter.json"))
		check(resumed.frames>held.frames+10,"foreground resumes simulation loop")
		backend.stop(handle)
		await wait_gone(handle)
		check(not backend.process_is_alive(int(first.pid)),"child process gone after shutdown")
		cancelled=handle
	if pids.size()==2:check(pids[0]!=pids[1],"restart uses a fresh process")
	print("ANDROID_LIFECYCLE ",JSON.stringify({"checks":checks,"failures":failures,"pids":pids,"error":backend.last_error()}))
	get_tree().quit(1 if failures else 0)
