extends SceneTree
var checks:=0
var failures:=[]
func check(ok: bool,label: String)->void:
	checks+=1
	if not ok:failures.append(label)
	print("PASS " if ok else "FAIL ",label)
func step(previous:Dictionary,last:Dictionary,frames:int,delta_usec:int,initial_usec:=1000000,initial_frames:=60)->Dictionary:
	var stable_usec:=initial_usec;var stable_frames:=initial_frames;var ready_usec:=0;var ready_frames:=0
	var resets:=0;var fallback_usec:=0;var fallback_frames:=0;var no_new_frame_wakeups:=0;var no_new_frame_usec:=0
	var now:=delta_usec;var previous_usec:=0
	var same_output: bool=last.matches and previous.matches and last.device_instance==previous.device_instance \
		and last.generation==previous.generation
	if same_output:
		if frames>0:
			# A long compile/driver stall must not count as seconds of rendering.
			var credited_usec:=mini(now-previous_usec,frames*100_000)
			stable_usec+=credited_usec;stable_frames+=frames
			ready_usec+=credited_usec;ready_frames+=frames
		else:
			# Separate rendering can emit frame_post_draw before the main
			# thread increments Engine.frames_drawn. This is not a fallback;
			# preserve the ready interval, but award no rendering time.
			no_new_frame_wakeups+=1;no_new_frame_usec+=now-previous_usec
	else:
		if stable_frames>0:resets+=1
		stable_usec=0;stable_frames=0
		fallback_usec+=now-previous_usec;fallback_frames+=frames
	return {"stable_usec":stable_usec,"stable_frames":stable_frames,"ready_usec":ready_usec,"ready_frames":ready_frames,"resets":resets,"fallback_usec":fallback_usec,"fallback_frames":fallback_frames,"no_new_frame_wakeups":no_new_frame_wakeups,"no_new_frame_usec":no_new_frame_usec}
func _initialize()->void:
	var ready:={"matches":true,"device_instance":1,"generation":9}
	var state:=step(ready,ready,0,12000)
	check(state.stable_usec==1000000 and state.stable_frames==60 and state.resets==0,"duplicate callback preserves uninterrupted interval")
	check(state.ready_usec==0 and state.ready_frames==0 and state.fallback_usec==0,"duplicate callback earns no rendering credit and no fallback time")
	check(state.no_new_frame_wakeups==1 and state.no_new_frame_usec==12000,"duplicate callback is explicitly observable")
	for i in 288:state=step(ready,ready,0,12000,state.stable_usec,state.stable_frames)
	check(state.stable_usec==1000000 and state.stable_frames==60,"288 duplicate callbacks cannot manufacture rendering time or reset the interval")
	state=step(ready,ready,1,20000,state.stable_usec,state.stable_frames)
	check(state.stable_usec==1020000 and state.stable_frames==61 and state.ready_usec==20000,"next actual frame continues the existing interval")
	state=step(ready,{"matches":false,"device_instance":1,"generation":9},0,30000)
	check(state.stable_usec==0 and state.stable_frames==0 and state.resets==1 and state.fallback_usec==30000,"real mismatch resets even without a new counted frame")
	state=step(ready,{"matches":true,"device_instance":2,"generation":9},1,20000)
	check(state.stable_usec==0 and state.resets==1 and state.fallback_frames==1,"device replacement resets the interval")
	state=step(ready,{"matches":true,"device_instance":1,"generation":10},1,20000)
	check(state.stable_usec==0 and state.resets==1 and state.fallback_frames==1,"generation replacement resets the interval")
	state=step(ready,ready,1,5000000)
	check(state.ready_usec==100000 and state.stable_usec==1100000,"five-second stall earns at most 100ms for one actual frame")
	state=step(ready,ready,2,5000000)
	check(state.ready_usec==200000 and state.ready_frames==2,"credit cap scales only with actual frame count")
	var report:={"checks":checks,"failures":failures,"status":"passed" if failures.is_empty() else "failed","note":"Executes the exact extracted current fixture accounting block under a headless Godot SceneTree; no GPU fixture or production code is run."}
	FileAccess.open("res://results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
