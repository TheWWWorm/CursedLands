extends SceneTree
## Standalone CPU diagnostic; no project resources or GPU are required.
## Run with --headless --script <this file> from an empty project directory.
## Godot 4.7's add_temporary() in modules/gdscript/gdscript_byte_codegen.cpp
## reuses NIL-pool slots without updating can_contain_object. A slot first used
## for packed data can then retain a RefCounted expression across awaits.
## The direct capture is a negative control: a future compiler fix may release
## it sooner. The synchronous capture must release before its coroutine ends.

class Probe extends RefCounted:
	var closed:=false
	func dispose() -> void:closed=true

class Holder extends RefCounted:
	var device: Probe
	func release() -> void:device.dispose();device=null

var failures: Array[String]=[]
var checks:=0

func _init() -> void:run.call_deferred()

func _holder() -> Holder:
	var result:=Holder.new();result.device=Probe.new()
	return result

func _capture(holder: Holder) -> WeakRef:
	var current: Object=holder.device
	return weakref(current) if is_instance_valid(current) else null

func _state(old: WeakRef) -> Dictionary:
	var owner=old.get_ref()
	return {"alive":owner!=null,"references_in_helper":owner.get_reference_count() if owner!=null else 0,
		"disposed":owner.closed if owner!=null else true}

func _sample(helper: bool) -> Dictionary:
	# Populate enough non-object temporary slots before the capture. Their
	# precise reuse depends on the rest of the coroutine's compiled expression.
	var seeded:=PackedByteArray().slice(0).slice(0).slice(0).slice(0).slice(0).slice(0).slice(0).slice(0) \
		.slice(0).slice(0).slice(0).slice(0).slice(0).slice(0).slice(0).slice(0)
	var holder:=_holder()
	var old: WeakRef
	if helper:old=_capture(holder)
	else:old=weakref(holder.device)
	holder.release.call_deferred()
	for i in 4:await process_frame
	return {"owner":old,"state":_state(old),"seed_bytes":seeded.size()}

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label)
	print("PASS " if ok else "FAIL ",label)

func run() -> void:
	var direct:=await _sample(false)
	check(direct.state.disposed,"direct negative-control owner is disposed")
	await process_frame # Let the completed sample's synchronous stack unwind.
	check(not _state(direct.owner).alive,"direct negative-control owner releases when its coroutine frame ends")
	var helper:=await _sample(true)
	check(not helper.state.alive,"synchronous weak capture releases the owner before the coroutine ends")
	await process_frame
	check(not _state(helper.owner).alive,"synchronous weak capture has no retained owner after return")
	var report:={"engine":Engine.get_version_info(),"checks":checks,"failures":failures,
		"direct_negative_control":direct.state,"synchronous_helper":helper.state,
		"known_temporary_retention_reproduced":direct.state.alive,
		"note":"Direct capture retention is a known compiler diagnostic, not a required behavior. Helper release is the regression gate."}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):
			var out:=arg.trim_prefix("--audit-out=");DirAccess.make_dir_recursive_absolute(out)
			FileAccess.open(out.path_join("path-weakref.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("PATH_TRACE_WEAKREF ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
