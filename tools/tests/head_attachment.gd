extends Node
## The original and smoothed bodies must retain identical head geometry and
## hair attachment throughout authored animation, with either head option.
var checks := 0
var failures := 0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func _ready()->void:
	for build:Vector3 in [Vector3(.5,.5,.5),Vector3(.1,.2,.8),Vector3(.9,.8,.2)]:
		var plain:=EIUnitModel.create({"prototype":"Human Hero","complexion":build,"smooth_joints":false})
		var smooth:=EIUnitModel.create({"prototype":"Human Hero","complexion":build,"smooth_joints":true})
		add_child(plain);add_child(smooth)
		plain.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		smooth.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		check(smooth._welded_head==null and smooth._head.get_child_count()>0,"head remains rigid with smoothed limbs")
		check(plain.has_detailed_head()==smooth.has_detailed_head(),"smoothing preserves portrait-head availability")
		for detailed:bool in [false,true]:
			plain.set_detailed_head(detailed);smooth.set_detailed_head(detailed)
			check(plain.detailed_head_shown()==smooth.detailed_head_shown(),"configured head choice retained")
			for act:String in ["idle","walk","run","attack"]:
				plain.act(act,1,0);smooth.play(plain._current,0,true)
				var clip:=plain.player.get_animation(plain.player.current_animation)
				var stable:=true
				for i in 31:
					var time:=clip.length*float(i)/30.0
					plain.player.seek(time,true);smooth.player.seek(time,true)
					var a:=plain._head.global_transform;var b:=smooth._head.global_transform
					stable=stable and a.is_equal_approx(b)
					var hair:=smooth._head.get_node_or_null("hr") as Node3D
					var original:=plain._head.get_node_or_null("hr") as Node3D
					if hair and original:stable=stable and hair.global_transform.is_equal_approx(original.global_transform)
				check(stable,act+": face and hair follow the same authored pose")
		plain.free();smooth.free()
	print("HEAD_ATTACHMENT ",JSON.stringify({"checks":checks,"failures":failures}));get_tree().quit(1 if failures else 0)
