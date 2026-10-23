extends SceneTree
const Device=preload("res://device.gd")
class Owner extends Device:
	var evidence:Dictionary
	func touch(value:int)->void:
		evidence.events.append(value);evidence.render_thread=OS.get_thread_caller_id()
		_notify(&"prepared",[true])
	func dispose()->void:
		evidence.events.append(99);super.dispose();evidence.closed=_closed
var checks:=0
var failures:=[]
var received:=0
func _init()->void:_run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
static func alive(reference:WeakRef)->bool:return reference.get_ref()!=null
static func hold(entered:Semaphore,resume:Semaphore)->void:entered.post();resume.wait()
static func done(semaphore:Semaphore)->void:semaphore.post()
func notified(ok:bool)->void:
	if ok:received+=1
func queue_owner(evidence:Dictionary)->WeakRef:
	var owner:=Owner.new();owner.evidence=evidence
	owner.prepared.connect(notified)
	var reference:WeakRef=weakref(owner)
	Device.dispatch(owner,&"touch",[41]);Device.dispatch(owner,&"touch",[42]);Device.dispatch(owner,&"dispose")
	return reference
static func ordinary()->Dictionary:
	var owner:=RefCounted.new()
	return {"owner":weakref(owner),"callback":owner.get_reference_count}
func _run()->void:
	var separate:=not RenderingServer.is_on_render_thread()
	var entered:=Semaphore.new();var resume:=Semaphore.new();var drained:=Semaphore.new()
	var evidence:={"events":[],"closed":false}
	if separate:
		RenderingServer.call_on_render_thread(hold.bind(entered,resume));entered.wait()
	var reference:=queue_owner(evidence)
	var queued_alive:=alive(reference)
	var control:=ordinary()
	if separate:resume.post()
	RenderingServer.call_on_render_thread(done.bind(drained));drained.wait()
	check(not alive(control.owner) and not control.callback.is_valid(),"ordinary Callable negative control releases target")
	check(queued_alive,"bound dispatch retains the last owner")
	check(evidence.events==[41,42,99] and evidence.closed,"operations execute in order before disposal")
	check((evidence.render_thread!=OS.get_main_thread_id())==separate,"expected rendering thread executes operations")
	check(alive(reference) and received==0,"deferred notifications retain owner until delivery")
	for i in 4:await process_frame
	check(received==2,"deferred notifications delivered after disposal")
	check(not alive(reference),"owner releases after dispatch and notifications drain")
	var report:={"checks":checks,"failures":failures,"separate_thread":separate,"main_thread":OS.get_main_thread_id(),"evidence":evidence}
	print(JSON.stringify(report))
	quit(1 if not failures.is_empty() else 0)
