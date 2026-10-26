extends Node
## Real authored clips across an attack/cast -> walking transition. Once a
## walking cycle settles, its torso and planted legs must share one stride.
var checks:=0
var failures:=[]
var cases:=[]
var unit:GameUnit
var pose:DirectPose
var doll:Paperdoll
func preview_errors() -> Vector2:
	# The unit-panel player is intentionally idle: the production preview
	# copies final part transforms, so compare those instead of clip metadata.
	doll._sync_pose(false)
	var lower:=pose.sample(pose.lower_clip,pose.phase)
	var source_inv:=unit.model.global_transform.affine_inverse()
	var preview_inv:=doll._model.global_transform.affine_inverse()
	var error:=Vector2.ZERO
	for pair:Array in doll._pairs:
		var part:=pair[0] as EIAnimPart
		var source:Transform3D=source_inv*part.global_transform
		var preview:Transform3D=preview_inv*(pair[1] as Node3D).global_transform
		var rotation:=preview.basis.get_rotation_quaternion().normalized()
		error.x=maxf(error.x,source.origin.distance_to(preview.origin))
		error.x=maxf(error.x,source.basis.get_rotation_quaternion().normalized().angle_to(rotation))
		error.y=maxf(error.y,(lower.rot[part] as Quaternion).normalized().angle_to(rotation))
	return error
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func advance(seconds:float) -> void:
	for i in ceili(seconds*60):
		pose.restore_pose();unit.model.player.advance(1.0/60);unit.model._process(1.0/60);pose.apply_pose(1.0/60)
func action(name:String) -> void:
	pose.restore_pose();unit.action=name;unit.model.act(name,1,0.0)
func stride_error() -> float:
	var lower:=pose.sample(pose.lower_clip,pose.phase)
	var maximum:=0.0
	for part:EIAnimPart in pose.parts:
		maximum=maxf(maximum,(lower.rot[part] as Quaternion).normalized().angle_to(part._world_key.normalized()))
	return maximum
func upper_stride_errors() -> Vector2:
	var model:=unit.model
	var phase:=pose.phase/model.player.get_animation("ei/"+pose.lower_clip).length
	var expected:=pose.sample(model._current,phase*model.player.get_animation("ei/"+model._current).length)
	var preview_inv:=doll._model.global_transform.affine_inverse()
	var error:=Vector2.ZERO
	for pair:Array in doll._pairs:
		var part:=pair[0] as EIAnimPart
		if part.name!="bd" and not String(model.get_path_to(part)).contains("/bd/"):continue
		var authored:Quaternion=(expected.rot[part] as Quaternion).normalized()
		var actual:Transform3D=preview_inv*(pair[1] as Node3D).global_transform
		error.x=maxf(error.x,authored.angle_to(part._world_key.normalized()))
		error.y=maxf(error.y,authored.angle_to(actual.basis.get_rotation_quaternion().normalized()))
	return error
func clock_error() -> float:
	var model:=unit.model
	var upper:=model.player.current_animation_position/model.player.get_animation("ei/"+model._current).length
	var lower:=pose.phase/model.player.get_animation("ei/"+pose.lower_clip).length
	return absf(wrapf(upper-lower,-.5,.5))
func controls() -> void:
	var rows:=[
		{"label":"ready forward walk","direction":Vector2.RIGHT,"ready":true,"running":false,"injury":0,"stamina":100.0},
		{"label":"ready sideways walk","direction":Vector2.DOWN,"ready":true,"running":false,"injury":0,"stamina":100.0},
		{"label":"backward walk","direction":Vector2.LEFT,"ready":false,"running":false,"injury":0,"stamina":100.0},
		{"label":"exhausted held run","direction":Vector2.RIGHT,"ready":true,"running":true,"injury":0,"stamina":0.0},
		{"label":"injured sideways walk","direction":Vector2.UP,"ready":true,"running":false,"injury":1,"stamina":100.0}]
	unit.set_meta("hero",{});unit.max_mana=100.0
	for row:Dictionary in rows:
		var model:=unit.model
		pose.restore_pose();model.weapon_type="sword";model.pose_state=EIUnitModel.ST_ATTACK;model.pose_mod=int(row.injury)*EIUnitModel.MOD_1
		unit.mana=row.stamina;unit.running=row.running;unit.direct_motion=row.direction;unit._move_speed=1.2
		action("attack");advance(.6)
		var phase_before:=pose.phase;var previous:=phase_before
		model.pose_state=EIUnitModel.ST_ATTACK if row.ready else EIUnitModel.ST_NEUTRAL
		action("walk")
		var max_step:=0.0;var samples:=0;var direction_ok:=true;var error:=Vector2.ZERO;var copy_error:=0.0
		for frame in 90:
			advance(1.0/60)
			var length:=model.player.get_animation("ei/"+pose.lower_clip).length
			var step:=wrapf(pose.phase-previous,-length*.5,length*.5);previous=pose.phase
			max_step=maxf(max_step,absf(step))
			if frame<20:continue
			direction_ok=direction_ok and (step<0.0 if row.direction==Vector2.LEFT else step>0.0)
			copy_error=maxf(copy_error,preview_errors().x)
			var current:=upper_stride_errors();error=Vector2(maxf(error.x,current.x),maxf(error.y,current.y));samples+=1
		var label:=String(row.label)
		var upper_code:=int(model._clip_records()[model._current].code)
		var lower_code:=int(model._clip_records()[pose.lower_clip].code)
		check(samples>=60 and error.x<.005,label+": ready/neutral upper clip uses the leg stride phase")
		check(error.y<.005 and copy_error<.005,label+": actual preview retains the same synchronized pose")
		check(clock_error()<.0001,label+": next action inherits the visible walking clock")
		check(max_step<.08 and direction_ok,label+": leg clock stays continuous through recovery and reversal")
		check((upper_code&0x38000)==model.pose_state,label+": authored ready/neutral upper stance is retained")
		check((lower_code&0x3c0000)==EIUnitModel.AC_WALK,label+": walking legs respect exhaustion and injury")
		check(unit.pos==Vector2.ZERO and unit._move_speed==1.2 and unit.running==row.running,label+": pose leaves authoritative movement/request intact")
		cases.append({"case":label,"source_upper_stride_error":error.x,"preview_upper_stride_error":error.y,"preview_copy_error":copy_error,"max_phase_step":max_step,"upper_clip":model._current,"lower_clip":pose.lower_clip})
func _ready() -> void:
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0},true)
	var world:=GameWorld.new();add_child(world);world.set_process(false);world.set_physics_process(false);world.zone={"type":"game"}
	unit=GameUnit.new();unit.setup(world,{"nid":1,"prototype":"Human Hero","position":Vector3.ZERO})
	world.add_child(unit);unit.set_process(false);unit.set_physics_process(false);unit.model.set_process(false)
	unit.model.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	unit.direct_controlled=true;unit.direct_motion=Vector2.RIGHT;unit._move_speed=1.2;unit.facing=0
	pose=DirectPose.new(unit);unit.add_child(pose);pose.set_process(false)
	doll=Paperdoll.new();doll.follow_pose=true;doll.exe_rect=UnitPanel.FIG;add_child(doll);doll.show_unit(unit);doll.set_process(false)
	check(unit.model.has_node("hp/bd") and not unit.model.adb.is_empty(),"original hero and animation database load")
	for one_shot:String in ["attack","cast"]:
		for gait:String in ["walk","run"]:
			for injury:int in [0,1,2]:
				var model:=unit.model
				pose.restore_pose();model.pose_state=EIUnitModel.ST_NEUTRAL;model.pose_mod=injury*EIUnitModel.MOD_1
				unit.running=gait=="run";unit.direct_motion=Vector2.RIGHT;unit._move_speed=1.2
				action(gait);advance(.43)
				model.pose_state=EIUnitModel.ST_ATTACK;action(one_shot);advance(.37)
				var chest:EIAnimPart=model.get_node("hp/bd")
				var upper_error:=0.0
				for frame in 12:
					pose.restore_pose();model.player.advance(1.0/60)
					var authored:=chest._world_key
					pose.apply_pose(1.0/60)
					upper_error=maxf(upper_error,authored.normalized().angle_to(chest._world_key.normalized()))
				var label:="%s -> %s, injury %d"%[one_shot,gait,injury]
				check(upper_error<.005,label+": committed upper action remains authored")
				model.pose_state=EIUnitModel.ST_NEUTRAL;action(gait);advance(.25)
				var max_error:=0.0;var preview_error:=Vector2.ZERO;var samples:=0;var prior_phase:=pose.phase;var progressed:=false
				for frame in 90:
					advance(1.0/60)
					progressed=progressed or not is_equal_approx(pose.phase,prior_phase);prior_phase=pose.phase
					if model._current==pose.lower_clip and pose.weight>=1:
						max_error=maxf(max_error,stride_error());samples+=1
						var current:=preview_errors();preview_error=Vector2(maxf(preview_error.x,current.x),maxf(preview_error.y,current.y))
				var code:=int(model._clip_records().get(pose.lower_clip,{}).get("code",-1))
				check(samples>=60,label+": matching source cycles are measured after recovery")
				check(max_error<.005,label+": whole walking body follows one authored stride")
				check(preview_error.x<.005,label+": actual unit-panel transforms mirror the final source pose")
				check(preview_error.y<.005,label+": visible unit-panel body follows the same authored stride")
				check(clock_error()<.0001,label+": next action inherits the visible walking clock")
				check(progressed and unit._move_speed==1.2 and unit.pos==Vector2.ZERO,label+": presentation advances without changing movement authority")
				check((code&0x3fc00000)==model.pose_mod or (injury>0 and (code&0x3fc00000)==0),label+": healthy/injured gait contract remains exact")
				cases.append({"case":label,"upper_action_error":upper_error,"stride_error":max_error,"preview_copy_error":preview_error.x,"preview_stride_error":preview_error.y,"samples":samples,"clip":pose.lower_clip})
	controls()
	pose.restore_pose();doll.free();world.free()
	var result:={"checks":checks,"failures":failures,"cases":cases}
	FileAccess.open("user://direct-attack-walk.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("DIRECT_ATTACK_WALK ",JSON.stringify(result));get_tree().quit(0 if failures.is_empty() else 1)
