extends Node
## Exact native sampling versus the previous per-track loop. Track edits,
## hierarchy changes and quaternion conventions remain visible in this call.
var checks := 0
var failures := 0
var pose_script: Variant = DirectPose
var kernel: RefCounted
class DerivedPart extends EIAnimPart:
	pass
class ScriptedAnimation extends Animation:
	pass
class Probe extends RefCounted:
	var calls := 0
	var decline := false
	func sample(_model,_parts,_animation,_time,_script,_absolute,_parent_first) -> Variant:
		calls+=1
		return null if decline else {"probe":true}

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		if failures<16:printerr("FAIL ",label)

func oracle(pose: DirectPose,clip: String,time: float) -> Dictionary:
	var rotations := {};var positions := {}
	var anim:=pose.model.player.get_animation("ei/"+clip)
	if anim==null:return {}
	for i in anim.get_track_count():
		var path:=anim.track_get_path(i)
		var n:=pose.model.get_node_or_null(NodePath(path.get_concatenated_names())) as EIAnimPart
		if n==null:continue
		if anim.track_get_type(i)==Animation.TYPE_VALUE:rotations[n]=anim.value_track_interpolate(i,time)
		elif anim.track_get_type(i)==Animation.TYPE_POSITION_3D:positions[n]=anim.position_track_interpolate(i,time)
	var world_rot:={}
	for n in pose.parts:
		var q:Quaternion=rotations.get(n,Quaternion.IDENTITY)
		var parent:Quaternion=world_rot.get(n.animation_parent,Quaternion.IDENTITY)
		world_rot[n]=q if EIAnim.absolute or n.animation_parent==null else parent*q if EIAnim.parent_first else q*parent
	return {"rot":world_rot,"pos":positions}

func compare(pose: DirectPose,clip: String,time: float,label: String) -> void:
	var expected:=oracle(pose,clip,time)
	var actual:=pose.sample(clip,time)
	check(actual==expected,label+" exact sampled values")
	check(actual.rot.keys()==expected.rot.keys() and actual.pos.keys()==expected.pos.keys(),label+" ordered node keys")

func track(animation: Animation,kind: int,path: NodePath,index: int) -> int:
	var id:=animation.add_track(kind);animation.track_set_path(id,path)
	for key in 4:
		var at:=float(key)/3.0
		if kind==Animation.TYPE_VALUE:
			animation.track_insert_key(id,at,Quaternion.from_euler(Vector3(.1+index*.23,key*.61-.2,index*.17-key*.11)))
		elif kind==Animation.TYPE_POSITION_3D:
			animation.position_track_insert_key(id,at,Vector3(index*.17,key*.13-.2,-index*.1))
	return id

func finish() -> void:
	print("DIRECT_POSE_NATIVE checks=",checks," failures=",failures)
	get_tree().quit(int(failures>0))

func metadata_checks(pose: DirectPose,library: AnimationLibrary,anim: Animation) -> void:
	var before:Dictionary=kernel.metadata_stats()
	compare(pose,"fixture",.4,"cached metadata samples current time")
	var after:Dictionary=kernel.metadata_stats()
	check(after.hits==before.hits+1 and after.rebuilds==before.rebuilds,"unchanged clip reuses only its track metadata")
	anim.track_swap(0,1);compare(pose,"fixture",.32,"same-frame track swap")
	anim.track_move_up(2);compare(pose,"fixture",.32,"same-frame track move up")
	anim.track_move_down(3);compare(pose,"fixture",.32,"same-frame track move down")
	anim.track_move_to(0,5);compare(pose,"fixture",.32,"same-frame track move to")
	track(anim,Animation.TYPE_VALUE,NodePath("part0:animation_key"),19)
	compare(pose,"fixture",.32,"same-frame added duplicate track wins")
	var replacement:=Animation.new()
	track(replacement,Animation.TYPE_VALUE,NodePath("part0:animation_key"),23)
	library.remove_animation("fixture");library.add_animation("fixture",replacement)
	compare(pose,"fixture",.32,"same-name replacement animation is sampled immediately")
	replacement.clear();compare(pose,"fixture",.32,"same-frame animation clear")
	track(replacement,Animation.TYPE_POSITION_3D,NodePath("part0:position"),2)
	compare(pose,"fixture",.32,"same-frame repopulated animation")
	var oversized:=Animation.new()
	for i in 513:
		var id:=oversized.add_track(Animation.TYPE_POSITION_3D)
		oversized.track_set_path(id,NodePath("part0:position"))
		oversized.position_track_insert_key(id,0,Vector3(i,0,0))
	library.add_animation("oversized",oversized)
	check(kernel.sample(pose.model,pose.parts,oversized,.3,EIAnimPart,false,false)==null,"track-count bound declines complete query")
	compare(pose,"oversized",.3,"oversized track count keeps complete script fallback")
	var long_paths:=Animation.new()
	for i in 480:
		var id:=long_paths.add_track(Animation.TYPE_POSITION_3D)
		long_paths.track_set_path(id,NodePath("absent".repeat(24)+str(i)+":position"))
		long_paths.position_track_insert_key(id,0,Vector3.ZERO)
	library.add_animation("long_paths",long_paths)
	check(kernel.sample(pose.model,pose.parts,long_paths,.3,EIAnimPart,false,false)==null,"track-path memory bound declines complete query")
	compare(pose,"long_paths",.3,"oversized paths keep complete script fallback")
	# A private helper makes retention and eviction assertions independent of
	# the fixture's previously sampled resources and AnimationPlayer connections.
	var transient:RefCounted=ClassDB.instantiate("DirectPoseKernel")
	var resource:Animation=Animation.new()
	var weak_resource: WeakRef = weakref(resource)
	check(transient.sample(pose.model,pose.parts,resource,.3,EIAnimPart,false,false)!=null,"temporary resource can be sampled")
	resource=null
	check(weak_resource.get_ref()==null,"metadata does not keep animation resources alive")
	var held:Array[Animation]=[]
	for i in 70:
		var clip:=Animation.new();held.append(clip)
		check(transient.sample(pose.model,pose.parts,clip,.3,EIAnimPart,false,false)!=null,"bounded-cache clip "+str(i))
		check(transient.metadata_stats().clips==mini(i+1,64),"expired metadata pruned and live cache bounded "+str(i))
	before=transient.metadata_stats()
	transient.sample(pose.model,pose.parts,held[0],.3,EIAnimPart,false,false)
	after=transient.metadata_stats()
	check(after.clips==64 and after.rebuilds==before.rebuilds+1,"evicted clip rebuilds metadata on reuse")
	var weak_kernel: WeakRef = weakref(transient)
	transient=null
	check(weak_kernel.get_ref()==null,"animation signal connections do not retain the helper")
	for clip in held:
		check(clip.get_signal_connection_list("changed").is_empty(),"helper destruction disconnects resource invalidators")

func _ready() -> void:
	check(ClassDB.class_exists("DirectPoseKernel"),"native pose sampler is available")
	if failures:finish();return
	kernel=pose_script._kernel
	check(kernel!=null and kernel.has_method("sample"),"production sampler uses the native helper")
	if failures:finish();return
	var old_absolute:=EIAnim.absolute;var old_parent_first:=EIAnim.parent_first
	var model:=EIUnitModel.new();add_child(model);model.set_process(false)
	model.player=AnimationPlayer.new();model.add_child(model.player)
	model.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var library:=AnimationLibrary.new();model.player.add_animation_library("ei",library)
	var pose:=DirectPose.new(null);model.add_child(pose);pose.set_process(false);pose.model=model
	for i in 7:
		var part:EIAnimPart=DerivedPart.new() if i==3 else EIAnimPart.new()
		part.name="part"+str(i)
		var parent:Node=model if i==0 else pose.parts[(i-1)/2]
		parent.add_child(part)
		part.animation_parent=parent as EIAnimPart
		if part.animation_parent:part.animation_parent.animation_children.append(part)
		pose.parts.append(part)
	var extra:=EIAnimPart.new();extra.name="extra";model.add_child(extra)
	var foreign:=Node3D.new();foreign.name="foreign";model.add_child(foreign)
	var anim:=Animation.new();anim.length=1.0
	library.add_animation("fixture",anim)
	for i in pose.parts.size():
		var path:=model.get_path_to(pose.parts[i])
		track(anim,Animation.TYPE_VALUE,NodePath(str(path)+":animation_key"),i)
		track(anim,Animation.TYPE_POSITION_3D,NodePath(str(path)+":position"),i)
	track(anim,Animation.TYPE_POSITION_3D,NodePath("extra:position"),11)
	track(anim,Animation.TYPE_VALUE,NodePath("foreign:rotation"),12)
	track(anim,Animation.TYPE_POSITION_3D,NodePath("missing:position"),13)
	track(anim,Animation.TYPE_VALUE,NodePath("part0:animation_key"),15) # last duplicate wins
	var ignored:=anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(ignored,NodePath("part0:quaternion"))
	anim.rotation_track_insert_key(ignored,0,Quaternion.IDENTITY)
	anim.rotation_track_insert_key(ignored,1,Quaternion(Vector3.UP,.7))
	var probe:=Probe.new();pose_script._kernel=probe
	check(pose.sample("fixture",.3)=={"probe":true} and probe.calls==1,"production performs one batch")
	probe.decline=true
	check(pose.sample("fixture",.3)==oracle(pose,"fixture",.3) and probe.calls==2,"declined query preserves script fallback")
	pose_script._kernel=null
	check(pose.sample("fixture",.3)==oracle(pose,"fixture",.3),"missing or older helper preserves script fallback")
	pose_script._kernel=kernel
	for absolute in [false,true]:
		for parent_first in [false,true]:
			EIAnim.absolute=absolute;EIAnim.parent_first=parent_first
			for looping in [Animation.LOOP_NONE,Animation.LOOP_LINEAR,Animation.LOOP_PINGPONG]:
				anim.loop_mode=looping
				for interpolation in [Animation.INTERPOLATION_NEAREST,Animation.INTERPOLATION_LINEAR,Animation.INTERPOLATION_CUBIC]:
					for i in anim.get_track_count():anim.track_set_interpolation_type(i,interpolation)
					for i in 80:
						var time:=float(i-12)/51.0
						compare(pose,"fixture",time,"synthetic %s/%s/%s/%s/%s"%[absolute,parent_first,looping,interpolation,i])
	# Every query resolves current resources and paths, without retained bindings.
	EIAnim.absolute=false;EIAnim.parent_first=false
	anim.track_set_enabled(0,false);compare(pose,"fixture",.31,"disabled tracks keep previous sampling semantics")
	anim.track_set_path(0,model.get_path_to(pose.parts[3]));compare(pose,"fixture",.31,"same-frame track retarget")
	anim.track_set_key_value(0,1,Quaternion(Vector3.FORWARD,.42));compare(pose,"fixture",.31,"same-frame key edit")
	pose.parts[2].animation_parent=null;compare(pose,"fixture",.31,"same-frame authored hierarchy edit")
	pose.parts[3].name="renamed";compare(pose,"fixture",.31,"node rename invalidates old track target")
	pose.parts[3].reparent(model);compare(pose,"fixture",.31,"node reparent invalidates old track target")
	anim.remove_track(0);compare(pose,"fixture",.31,"track removal is immediate")
	pose.parts.reverse();compare(pose,"fixture",.31,"explicit part order remains significant");pose.parts.reverse()
	var empty:=Animation.new();library.add_animation("empty",empty)
	compare(pose,"empty",.31,"empty animation retains identity hierarchy")
	var scripted:=ScriptedAnimation.new();scripted.length=1.0
	track(scripted,Animation.TYPE_VALUE,NodePath("part0:animation_key"),0)
	library.add_animation("scripted",scripted)
	check(kernel.sample(model,pose.parts,scripted,.31,EIAnimPart,false,false)==null,"scripted animation declines before interpolation")
	compare(pose,"scripted",.31,"scripted animation uses the full fallback")
	check(kernel.sample(null,pose.parts,anim,.3,EIAnimPart,false,false)==null,"missing model declines")
	check(kernel.sample(model,pose.parts,null,.3,EIAnimPart,false,false)==null,"missing animation declines")
	check(kernel.sample(model,pose.parts,Resource.new(),.3,EIAnimPart,false,false)==null,"unsupported resource declines")
	check(kernel.sample(model,pose.parts,anim,.3,null,false,false)==null,"missing part script declines")
	metadata_checks(pose,library,anim)
	model.free()
	# Sample all authored tracks, then run an isolated matched CPU comparison.
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	model=EIUnitModel.create({"prototype":"Human Hero"},true);add_child(model);model.set_process(false)
	model.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	pose=DirectPose.new(null);model.add_child(pose);pose.set_process(false);pose.model=model
	for root in model._animation_roots:pose.collect(root)
	var clips:Array[String]=[]
	for action in ["idle","walk","run","attack","cast","death"]:
		var clip:=model.resolve(action)
		if clip.is_empty():continue
		clips.append(clip)
		var length:=model.player.get_animation("ei/"+clip).length
		for absolute in [false,true]:
			for parent_first in [false,true]:
				EIAnim.absolute=absolute;EIAnim.parent_first=parent_first
				for frame in 30:compare(pose,clip,length*float(frame)/29.0,"authored "+action)
	check(clips.size()==6,"all authored action fixtures are present")
	EIAnim.absolute=old_absolute;EIAnim.parent_first=old_parent_first
	var timings:=[]
	for native in [false,true,true,false]:
		pose_script._kernel=kernel if native else null
		var started:=Time.get_ticks_usec()
		for frame in 600:pose.sample(clips[frame%clips.size()],float(frame%37)*.017)
		timings.append({"native":native,"samples":600,"usec":Time.get_ticks_usec()-started})
	print("DIRECT_POSE_NATIVE_TIMING ",JSON.stringify(timings))
	pose_script._kernel=kernel;model.free();finish()
