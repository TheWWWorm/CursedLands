extends Node
## Large live terrain gathers must not do their topology/packing work in begin
## or in one render-thread phase. Compare the bounded worker with the original
## synchronous calculation, including posed geometry and exact welded seams.
const HELPER := "res://src/game/fx/path_trace_terrain_sun.gd"
const WORK_LIMIT := 73
const GRID_WIDTH := 128
const GRID_HEIGHT := 96
const EXPECTED_CORNERS := GRID_WIDTH*GRID_HEIGHT*6+6
const EXPECTED_SAMPLES := (GRID_WIDTH+1)*(GRID_HEIGHT+1)+4
var checks := 0
var failures := 0
var out := "user://terrain-sun-budget"
var observations := {}
var helper_path := HELPER

func check(ok: bool, label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func _ready() -> void:
	run.call_deferred()

func grid(width: int,height: int,origin: Vector3) -> PackedByteArray:
	var values:=PackedFloat32Array();values.resize(width*height*6*16);values.fill(0.0)
	var cursor:=0
	var corners: Array[Vector2i]=[Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]
	for z in height:
		for x in width:
			for corner: Vector2i in corners:
				var px:=origin.x+x+corner.x
				var pz:=origin.z+z+corner.y
				var py:=origin.y+float(posmod(int(px),4))*0.025
				values[cursor]=px;values[cursor+1]=py;values[cursor+2]=pz
				values[cursor+5]=1.0
				for channel in range(8,12):values[cursor+channel]=1.0
				cursor+=16
	return values.to_byte_array()

func grid_fixture() -> Dictionary:
	var left:=grid(GRID_WIDTH/2,GRID_HEIGHT,Vector3.ZERO)
	var right_rest:=grid(GRID_WIDTH/2,GRID_HEIGHT,Vector3(GRID_WIDTH/2,0.5,0))
	var right_pose:=grid(GRID_WIDTH/2,GRID_HEIGHT,Vector3(GRID_WIDTH/2,0,0))
	var foreign:=grid(1,1,Vector3(-10,0,-10))
	var ordinary:=grid(1,1,Vector3.ZERO)
	var data:=PackedByteArray();var geometry: Array=[];var placements: Array=[]
	for record: Dictionary in [{"bytes":left,"terrain":true},{"bytes":right_rest,"terrain":true},
		{"bytes":foreign,"terrain":true},{"bytes":ordinary,"terrain":false}]:
		geometry.append({"offset":data.size()/64,"count":record.bytes.size()/64,"terrain":record.terrain})
		placements.append({"geometry":geometry.size()-1,"transform":Transform3D.IDENTITY,"mask":7})
		data.append_array(record.bytes)
	return {"data":data,"geometry":geometry,"placements":placements,"poses":[{"geometry":1,"data":right_pose}]}

func small_fixture() -> Dictionary:
	return {"data":grid(1,1,Vector3(4,0,5)),"geometry":[{"offset":0,"count":6,"terrain":true}],
		"placements":[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7}],"poses":[]}

func bridge_fixture(masks: Array) -> Dictionary:
	var placements: Array=[]
	for index in masks.size():
		placements.append({"geometry":0,"transform":Transform3D(Basis.IDENTITY,Vector3(index,0,0)),"mask":masks[index]})
	var data:=grid(1,1,Vector3.ZERO)
	# Identical translated quads share exact endpoints only when this small
	# bridge is flat; the large-grid fixture deliberately varies its heights.
	for vertex in 6:data.encode_float(vertex*64+4,0.0)
	return {"data":data,"geometry":[{"offset":0,"count":6,"terrain":true}],
		"placements":placements,"poses":[]}

func component_id(data: PackedByteArray,instance: int) -> int:
	var base:=data.decode_u32(32+instance*4)
	return data.decode_u32(data.decode_u32(20)+(base/3)*4)

func component_flags_are(data: PackedByteArray,component: int,value: int) -> bool:
	var found:=false
	for sample_index: int in int(data.decode_u32(12)):
		var at: int=data.decode_u32(8)+sample_index*32
		if data.decode_u32(at+20)!=component:continue
		found=true
		if data.decode_u32(at+24)!=value:return false
	return found

func all_flags_are(data: PackedByteArray,value: int) -> bool:
	for sample_index: int in int(data.decode_u32(12)):
		if data.decode_u32(data.decode_u32(8)+sample_index*32+24)!=value:return false
	return true

func active_component_checks(script: Script,large: PackedByteArray) -> void:
	check(large.decode_u32(24)==2 and large.decode_u32(28)==0xffffffff and all_flags_are(large,1),
		"large posed grid identifies both active components and marks their samples active")
	var cases: Array=[{"name":"joined","masks":[7,7,7]},
		{"name":"hidden-bridge","masks":[7,0,7]},
		{"name":"single-active-last","masks":[0,0,7]},
		{"name":"visible-nonshadow-bridge","masks":[7,1,7]},
		{"name":"all-hidden","masks":[0,0,0]}]
	var equivalent:=true
	for test: Dictionary in cases:
		var fixture:=bridge_fixture(test.masks)
		var reference: RefCounted=script.new();var worker: RefCounted=script.new()
		var accepted: bool=reference.prepare(fixture.data,fixture.geometry,fixture.placements,fixture.poses)
		var expected: PackedByteArray=reference._pack_inputs()
		begin(worker,fixture);var result:=await drain(worker,"active-"+test.name)
		var actual: PackedByteArray=worker.prepared_data()
		equivalent=equivalent and accepted and result.status==OK and result.bounded and actual==expected
		var valid:=false
		if not actual.is_empty():
			var active:=actual.decode_u32(24);var sole:=actual.decode_u32(28)
			var first:=component_id(actual,0);var middle:=component_id(actual,1);var last:=component_id(actual,2)
			match test.name:
				"joined":valid=active==1 and sole==first and first==middle and middle==last and all_flags_are(actual,1)
				"hidden-bridge","visible-nonshadow-bridge":
					valid=active==2 and sole==0xffffffff and first!=middle and middle!=last and first!=last \
						and component_flags_are(actual,first,1) and component_flags_are(actual,middle,0) and component_flags_are(actual,last,1)
				"single-active-last":valid=active==1 and sole==last and last!=first and component_flags_are(actual,first,0) \
					and component_flags_are(actual,middle,0) and component_flags_are(actual,last,1)
				"all-hidden":valid=active==0 and sole==0xffffffff and all_flags_are(actual,0)
		check(valid,test.name+": shadow-casting count, sole ID and per-sample active flags match actual masks and connectivity")
		worker.dispose();reference.dispose()
	check(equivalent,"active and inactive component metadata stays byte-identical between synchronous and bounded preparation")

func begin(helper: RefCounted,fixture: Dictionary) -> int:
	var start:=Time.get_ticks_usec()
	helper.begin_prepare(fixture.data,fixture.geometry,fixture.placements,fixture.poses)
	return Time.get_ticks_usec()-start

func drain(helper: RefCounted,label: String,limit:=WORK_LIMIT) -> Dictionary:
	var prior: Dictionary=helper.preparation_stats()
	var total_work: int=prior.total_work
	var steps:=0;var bounded:=true;var busy_state:=true;var code:=ERR_BUSY
	var peak:=0;var elapsed:=0;var samples: Array[int]=[]
	# A generous time allowance isolates the deterministic work cap. Record
	# actual timings, but do not make machine load a pass/fail criterion.
	while code==ERR_BUSY and steps<20000:
		var start:=Time.get_ticks_usec()
		code=helper.prepare_step(1000000,limit)
		var duration:=Time.get_ticks_usec()-start
		elapsed+=duration;peak=maxi(peak,duration);samples.append(duration);steps+=1
		var stats: Dictionary=helper.preparation_stats()
		bounded=bounded and stats.last_work>=0 and stats.last_work<=limit
		total_work+=int(stats.last_work)
		busy_state=busy_state and (helper.is_preparing() if code==ERR_BUSY else not helper.is_preparing())
		if steps%256==0:await get_tree().process_frame
	var stats: Dictionary=helper.preparation_stats()
	samples.sort()
	var row:={"status":code,"steps":steps,"bounded":bounded,"busy_state":busy_state,
		"reported_work":stats.total_work,"summed_work":total_work,"wall_us":elapsed,"max_step_us":peak,
		"median_step_us":samples[samples.size()/2] if not samples.is_empty() else 0,"worker_stats":stats}
	observations[label]=row
	return row

func background_begin(helper: RefCounted,fixture: Dictionary,label: String) -> int:
	var start:=Time.get_ticks_usec()
	var status: int=helper.begin_background_prepare(fixture.data,fixture.geometry,fixture.placements,fixture.poses)
	observations[label+"-launch"]={"status":status,"caller_us":Time.get_ticks_usec()-start,"state":helper.background_state()}
	return status

func background_reference(helper: RefCounted,references: Array[WeakRef]) -> WeakRef:
	var job: RefCounted=helper.get("_background_job")
	if job==null:return null
	var reference: WeakRef = weakref(job);references.append(reference)
	return reference

func released(reference: WeakRef) -> bool:
	return reference!=null and reference.get_ref()==null

func joined(helper: RefCounted) -> bool:
	var state: Dictionary=helper.background_state()
	return not state.running and not state.pending and state.started==state.joined_count

func background_wait(helper: RefCounted,label: String) -> Dictionary:
	var deadline:=Time.get_ticks_msec()+10000
	var start:=Time.get_ticks_usec();var status:=ERR_BUSY;var polls:=0;var maximum:=0
	while status==ERR_BUSY and Time.get_ticks_msec()<deadline:
		var before:=Time.get_ticks_usec()
		status=helper.prepare_step()
		maximum=maxi(maximum,Time.get_ticks_usec()-before);polls+=1
		if status==ERR_BUSY:await get_tree().process_frame
	var row:={"status":status,"polls":polls,"elapsed_us":Time.get_ticks_usec()-start,
		"max_caller_poll_us":maximum,"state":helper.background_state()}
	observations[label]=row
	return row

func background_checks(script: Script,large: Dictionary,small: Dictionary,expected: PackedByteArray,small_expected: PackedByteArray) -> void:
	var worker: RefCounted=script.new()
	var supported:=worker.has_method("begin_background_prepare") and worker.has_method("background_state")
	check(supported,"terrain preparation supports isolated background work with observable worker lifetime")
	if not supported:worker.dispose();return
	var references: Array[WeakRef]=[]
	var snapshot:=large.duplicate(true)
	var status:=background_begin(worker,snapshot,"background-large")
	var first_job:=background_reference(worker,references)
	check(status==OK and first_job!=null,"background preparation launches a private worker")
	check(worker.prepared_data().is_empty(),"a background result remains unpublished until the caller adopts it")
	# The caller may release or replace its descriptors after enqueueing. A
	# worker must use its private snapshot, including initial pose dictionaries.
	snapshot.geometry[0].terrain=false;snapshot.geometry[1].count=0
	snapshot.placements[0].mask=0;snapshot.placements[1].transform=Transform3D(Basis.IDENTITY,Vector3(200,0,0))
	snapshot.poses[0].data=PackedByteArray();snapshot.data=PackedByteArray()
	var result:=await background_wait(worker,"background-large")
	check(result.status==OK and worker.prepared_data()==expected and worker._components==2,
		"background output matches the synchronous posed snapshot despite caller descriptor changes")
	var state: Dictionary=result.state
	check(state.worker_thread_id!=state.launch_thread_id and str(state.worker_thread_id)!="" and str(state.worker_thread_id)!="0",
		"terrain iteration actually executes on a different thread from its caller")
	check(joined(worker) and released(first_job),"adopting a completed result joins and releases its worker")
	status=background_begin(worker,large,"background-cancel")
	var cancelled_job:=background_reference(worker,references)
	check(status==OK and cancelled_job!=null,"launch a fresh worker for pending cancellation")
	await get_tree().process_frame
	var before_state: Dictionary=worker.background_state()
	var before:=Time.get_ticks_usec();worker.cancel_prepare()
	observations["background-cancel"]={"caller_us":Time.get_ticks_usec()-before,"before":before_state,"state":worker.background_state()}
	check(joined(worker) and released(cancelled_job) and worker.prepared_data().is_empty(),
		"cancellation joins the pending worker and never publishes its partial result")
	status=background_begin(worker,small,"background-restart")
	var restart_job:=background_reference(worker,references)
	result=await background_wait(worker,"background-restart")
	check(status==OK and result.status==OK and worker.prepared_data()==small_expected,
		"a cancelled background preparer restarts with only the new fixture's result")
	check(joined(worker) and released(restart_job),"the restarted worker is reclaimed after adoption")
	background_begin(worker,large,"background-replaced-old")
	var replaced_job:=background_reference(worker,references)
	status=background_begin(worker,small,"background-replacement")
	var replacement_job:=background_reference(worker,references)
	check(status==OK and released(replaced_job),"starting a new background gather joins the superseded worker")
	result=await background_wait(worker,"background-replacement")
	check(result.status==OK and worker.prepared_data()==small_expected,"replacement cannot adopt stale bytes from the superseded gather")
	check(joined(worker) and released(replacement_job),"replacement leaves no surviving worker")
	background_begin(worker,large,"background-dispose")
	var disposed_job:=background_reference(worker,references)
	await get_tree().process_frame
	before_state=worker.background_state()
	before=Time.get_ticks_usec();worker.dispose()
	observations["background-dispose"]={"caller_us":Time.get_ticks_usec()-before,"before":before_state,"state":worker.background_state()}
	check(joined(worker) and released(disposed_job) and worker.prepared_data().is_empty(),
		"disposing a pending preparer joins its worker without needing a RenderingDevice")
	# Two independent owners must never share cancellation or mutable results.
	var other: RefCounted=script.new();worker=script.new()
	background_begin(worker,large,"background-independent-cancel")
	var independent_cancelled:=background_reference(worker,references)
	background_begin(other,small,"background-independent-complete")
	var independent_complete:=background_reference(other,references)
	worker.cancel_prepare();result=await background_wait(other,"background-independent-complete")
	check(result.status==OK and other.prepared_data()==small_expected,"cancelling one owner cannot cancel or corrupt another owner's worker")
	check(joined(worker) and joined(other) and released(independent_cancelled) and released(independent_complete),
		"both independent owners reclaim their workers")
	other.dispose()
	var malformed:=large.duplicate(true);malformed.poses[0].data=PackedByteArray()
	background_begin(worker,malformed,"background-invalid-pose")
	var failed_job:=background_reference(worker,references)
	result=await background_wait(worker,"background-invalid-pose")
	check(result.status==ERR_INVALID_DATA and worker.prepared_data().is_empty(),"an invalid initial pose reports failure without publishing cache bytes")
	check(joined(worker) and released(failed_job),"a failed worker is joined and released")
	background_begin(worker,small,"background-after-failure")
	var recovered_job:=background_reference(worker,references)
	result=await background_wait(worker,"background-after-failure")
	check(result.status==OK and worker.prepared_data()==small_expected and joined(worker) and released(recovered_job),
		"a failed background build can restart successfully without retaining its worker")
	worker.dispose()
	var all_released:=references.size()==10
	for reference: WeakRef in references:all_released=all_released and released(reference)
	check(all_released,"all ten completed, cancelled, replaced, disposed and failed workers have been released")

func readiness_gate_checks() -> void:
	var base_path:=helper_path.get_base_dir().path_join("water_raytrace_device.gd")
	var probe:=GDScript.new()
	# Exercise the real scheduler without creating any RenderingDevice. The
	# overridden phase records entry and stops before resource allocation.
	probe.source_code="extends %s\nvar probe_gate := false\nvar probe_advances := 0\nfunc build_extra_ready() -> bool:\n\treturn probe_gate\nfunc _advance_resource_build() -> bool:\n\tprobe_advances += 1\n\treturn false\n"%JSON.stringify(base_path)
	var valid:=probe.reload()==OK and probe.can_instantiate()
	check(valid,"CPU scheduler probe loads the real resource-build readiness hook")
	if not valid:return
	var device: RefCounted=probe.new()
	device._building=true;device._build_resource_stage=5
	device.build_step(6000)
	check(device.probe_advances==0 and device._build_resource_stage==5,
		"a pending background phase returns without spinning resource-build work to the deadline")
	device.probe_advances=0;device.probe_gate=true;device.build_step(6000)
	check(device.probe_advances==1,"a ready background phase still advances resource construction")
	device.probe_gate=false;device.probe_advances=0;device._build_resource_stage=2
	device.build_step(6000)
	check(device.probe_advances==1,"ordinary resource phases advance independently of the optional background gate")
	device.dispose()

func finish() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out.path_join("terrain-sun-budget.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"helper":helper_path,
		"helper_sha256":FileAccess.get_file_as_string(helper_path).sha256_text(),"observations":observations},"\t"))
	print("PT_TERRAIN_SUN_BUDGET ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
		if arg.begins_with("--terrain-sun-helper="):helper_path=arg.trim_prefix("--terrain-sun-helper=")
	var script: Script=load(helper_path)
	check(script!=null and script.can_instantiate(),"terrain sunlight preparation loads without GPU resources")
	if script==null or not script.can_instantiate():finish();return
	var worker: RefCounted=script.new()
	var supported:=true
	for method: String in ["begin_prepare","prepare_step","cancel_prepare","is_preparing","prepared_data","preparation_stats"]:
		supported=supported and worker.has_method(method)
	check(supported,"terrain sunlight exposes resumable preparation and cancellation")
	if not supported:finish();return
	var large:=grid_fixture();var small:=small_fixture()
	check(large.data.size()>4000000 and large.geometry[0].count+large.geometry[1].count==GRID_WIDTH*GRID_HEIGHT*6,
		"fixture covers a production-sized terrain stream across separate placements")
	var synchronous: RefCounted=script.new()
	var start:=Time.get_ticks_usec()
	check(synchronous.prepare(large.data,large.geometry,large.placements,large.poses),"synchronous reference accepts the posed terrain stream")
	var expected: PackedByteArray=synchronous._pack_inputs()
	observations["synchronous_us"]=Time.get_ticks_usec()-start
	check(synchronous._components==2,"posed grid halves weld while the separate terrain patch remains independent")
	check(expected.decode_u32(12)==EXPECTED_SAMPLES,"welded sample count matches the independently calculated grid vertices")
	check(synchronous._corner_capacity==EXPECTED_CORNERS and expected.decode_u32(32+3*4)==0xffffffff,
		"only terrain corners participate and the ordinary placement has no terrain sample base")
	var rest: RefCounted=script.new()
	check(rest.prepare(large.data,large.geometry,large.placements) and rest._components==3,
		"omitting the initial pose leaves the two grid halves disconnected")
	observations["begin_us"]=begin(worker,large)
	check(worker.is_preparing() and worker.prepared_data().is_empty() and worker.preparation_stats().total_work==0,
		"begin defers all terrain iteration and does not publish incomplete cache input")
	var first: int=worker.prepare_step(1000000,WORK_LIMIT)
	var first_stats: Dictionary=worker.preparation_stats()
	check(first==ERR_BUSY and first_stats.last_work>0 and first_stats.last_work<=WORK_LIMIT,
		"one bounded step cannot finish the large terrain gather")
	var completed:=await drain(worker,"large")
	check(completed.bounded and completed.busy_state,"every resumed step obeys its work cap and reports pending state accurately")
	check(completed.status==OK and not worker.is_preparing(),"bounded preparation eventually completes")
	check(completed.steps>100,"large topology and packing require many separate bounded steps")
	check(completed.reported_work==completed.summed_work,"work counters account for every unit across resumptions")
	check(worker._components==synchronous._components and worker._component_corners==synchronous._component_corners and worker._bases==synchronous._bases,
		"bounded topology matches the synchronous posed connectivity and primitive map")
	check(worker.prepared_data()==expected,"bounded serialized cache input is byte-identical to the synchronous calculation")
	begin(worker,large);worker.prepare_step(1000000,WORK_LIMIT);worker.cancel_prepare()
	check(not worker.is_preparing() and worker.prepared_data().is_empty(),"cancellation releases the incomplete preparation without publishing it")
	var small_sync: RefCounted=script.new();small_sync.prepare(small.data,small.geometry,small.placements,small.poses)
	var small_expected: PackedByteArray=small_sync._pack_inputs()
	begin(worker,small);var restarted:=await drain(worker,"restart-small")
	check(restarted.status==OK and not worker.is_preparing(),"a cancelled worker can restart and complete")
	check(worker.prepared_data()==small_expected,"restart contains only the new fixture's cache bytes")
	check(worker._components==1 and worker._corner_capacity==6 and worker.prepared_data().decode_u32(12)==4,
		"restart drops all old topology and welded sample state")
	begin(worker,large);worker.prepare_step(1000000,WORK_LIMIT);begin(worker,small)
	var replaced:=await drain(worker,"replace-pending")
	check(replaced.status==OK and worker.prepared_data()==small_expected,"a new begin safely replaces a still-pending gather")
	begin(worker,large);worker.prepare_step(1000000,WORK_LIMIT);worker.dispose()
	check(not worker.is_preparing() and worker.prepared_data().is_empty(),"disposing a pending gather cancels its CPU work without needing a GPU")
	worker=script.new();begin(worker,small)
	var tiny:=await drain(worker,"one-unit",1)
	check(tiny.status==OK and tiny.bounded and tiny.steps>10,"a one-unit work cap is respected through every preparation phase")
	check(worker.prepared_data()==small_expected,"one-unit resumptions preserve deterministic output bytes")
	var empty:=small.duplicate(true);empty.geometry[0].terrain=false
	var empty_sync: RefCounted=script.new();empty_sync.prepare(empty.data,empty.geometry,empty.placements,empty.poses)
	begin(worker,empty);var no_terrain:=await drain(worker,"no-terrain",1)
	check(no_terrain.status==OK and worker._components==0 and worker.prepared_data()==empty_sync._pack_inputs(),
		"an ordinary-only stream completes with the same empty terrain input as the synchronous path")
	await active_component_checks(script,expected)
	await background_checks(script,large,small,expected,small_expected)
	readiness_gate_checks()
	worker.dispose();synchronous.dispose();rest.dispose();small_sync.dispose();empty_sync.dispose()
	finish()
