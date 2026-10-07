extends Node
var checks:=0
var failures:=0

class RayWorld extends GameWorld:
	var factor:=1.0
	var rays:Array=[]
	func sight_ray(a:GameUnit,b:GameUnit)->float:
		rays.append([a.uid,b.uid])
		return factor

class CustomUnit extends GameUnit:
	func detect(_i:int)->float:return 100.0

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL ",label)

func scalar(w:GameWorld,u:GameUnit,rows:Array,k:PackedFloat64Array,keep:Dictionary,corpses:Dictionary)->Array:
	var result:=[];var seen:={}
	for target in rows:
		if not is_instance_valid(target) or not target is GameUnit or target.hidden:continue
		var id:int=target.get_instance_id()
		if (corpses if target.dead else keep).has(id) or seen.has(id):continue
		seen[id]=true
		if k.is_empty():k=w.ai.notice_terms(u,float(u.stats.sight))
		if w.ai.can_notice_with(u,target,k):result.append(target)
	return result

func state(u:GameUnit)->Dictionary:
	var result:={}
	for key in u.get_meta_list():result[key]=u.get_meta(key)
	return result.duplicate(true)

func restore(u:GameUnit,record:Dictionary)->void:
	for key in u.get_meta_list():u.remove_meta(key)
	for key in record:u.set_meta(key,record[key].duplicate(true) if record[key] is Dictionary or record[key] is Array else record[key])

func adapter(kernel:RefCounted)->void:
	# Exercise the real adapter, including drop/add ordering, corpse suspicion,
	# diplomacy changes and same-tick memoization, not only its numeric kernel.
	var w:=GameWorld.new();var u:=GameUnit.new()
	u.world=w;u.uid=1;u.stats={"sight":15.0};u.faction=1
	u.proto={"senses":[15.0,100.0,5.0],"peripheral_skills":3.0}
	w.set_unit(u.uid,u)
	var rows:=[]
	for i in 32:
		var target:=GameUnit.new();target.uid=i+2;target.world=w
		target.faction=i%4;target.controller=0 if i%5==0 else -1
		target.pos=Vector2.from_angle(float(i)*0.31)*float(i)
		target.proto={"detection":[1.0,1.0,1.0]}
		rows.append(target);w.set_unit(target.uid,target)
	for trial in 120:
		w.time=float(trial)*GameUnit.TICK
		u.controller=0 if trial%3==0 else -1;u.facing=float(trial)*0.2
		w.set_relation(1,trial%4,trial%3)
		var changed:GameUnit=rows[trial%rows.size()]
		changed.dead=trial%5==0;changed.hidden=trial%7==0
		changed.pos=Vector2(float(trial%40)-20.0,float(trial%9))
		changed.buffs={"sneak":{"detect":[0,-1.0]}} if trial%4==0 else {}
		var before:=state(u)
		w.ai._perception=null
		seed(77900+trial)
		var expected:=w.ai.player_perceive(u,trial%4==0).duplicate()
		var after:=state(u)
		restore(u,before);w.ai._perception=kernel
		seed(77900+trial)
		check(w.ai.player_perceive(u,trial%4==0)==expected,"adapter noticed "+str(trial))
		check(state(u)==after,"adapter metadata and suspicion "+str(trial))
		check(w.ai.player_perceive(u)==expected,"same-tick memoization "+str(trial))
	for target in rows:target.free()
	u.free();w.free()

func _ready()->void:
	var kernel:RefCounted=ClassDB.instantiate("PerceptionKernel")
	var w:=RayWorld.new();var u:=GameUnit.new();u.world=w;u.uid=1;u.stats={"sight":15.0}
	var rows:=[]
	for i in 32:
		var t:=GameUnit.new();t.world=w;t.uid=i+2;rows.append(t)
	var rng:=RandomNumberGenerator.new();rng.seed=7740651
	var native_us:=0;var script_us:=0
	for trial in 1200:
		u.pos=Vector2(rng.randf_range(-50,50),rng.randf_range(-50,50));u.facing=rng.randf_range(-50,50)
		w.factor=[0.0,0.0001,0.00010001,0.25,0.5,1.0][trial%6]
		var keep:={};var corpses:={}
		for i in rows.size():
			var t:GameUnit=rows[i]
			t.pos=u.pos+Vector2.from_angle(rng.randf_range(-PI,PI))*rng.randf_range(0,50)
			t.stance=i%3;t.action="cast:8" if i%4==0 else "walk"
			t.hidden=(i+trial)%13==0;t.dead=(i+trial)%7==0
			t.proto={"detection":[rng.randf_range(-1,3),1.0,rng.randf_range(-1,3)]}
			if trial%3==1:t.proto.detection=PackedFloat32Array(t.proto.detection)
			elif trial%3==2:t.proto.detection=PackedFloat64Array(t.proto.detection)
			t.buffs={"first":{"detect":[0,rng.randf_range(-1,1)]},"second":{"detect":[0,rng.randf_range(-1,1)]},"life":{"detect":[2,rng.randf_range(-1,1)]}}
			if i%9==trial%9:(corpses if t.dead else keep)[t.get_instance_id()]=t
		var terms:=PackedFloat64Array([rng.randf_range(0,30),rng.randf_range(0,1),rng.randf_range(0,PI),rng.randf_range(0,5),rng.randf_range(0,20)])
		if trial%11==0:terms=PackedFloat64Array()
		w.rays.clear();var before:=Time.get_ticks_usec()
		var expected:=scalar(w,u,rows,terms,keep,corpses);script_us+=Time.get_ticks_usec()-before
		var rays:=w.rays.duplicate(true);w.rays.clear();before=Time.get_ticks_usec()
		var actual:Array=kernel.new_visible(rows,GameUnit,u,w,w.ai,terms,keep,corpses,float(u.stats.sight));native_us+=Time.get_ticks_usec()-before
		check(actual==expected,"visible candidates/order "+str(trial))
		check(w.rays==rays,"occlusion calls/order "+str(trial))
	# Exact distance and angle boundaries, including the strict final sight
	# comparison and peripheral detection of an invisible living/dead target.
	u.pos=Vector2.ZERO;u.facing=0.0
	var t:GameUnit=rows[0];t.hidden=false;t.buffs={};t.stance=0;t.action="idle"
	for detection in [0.0,1.0]:
		t.proto={"detection":[detection,1.0,0.0]}
		for dead in [false,true]:
			t.dead=dead
			for point in [Vector2.ZERO,Vector2(10,0),Vector2(9.999999,0),Vector2(10.000001,0),Vector2(0,10),Vector2(-10,0)]:
				t.pos=point
				for ray in [0.0,0.0001,0.00010001,1.0]:
					w.factor=ray
					var terms:=PackedFloat64Array([10.0,1.0,PI*.5,10.0,0.0])
					check(kernel.new_visible([t,t],GameUnit,u,w,w.ai,terms,{},{},10.0)==scalar(w,u,[t,t],terms,{},{}),"boundary/duplicate")
	var custom:=CustomUnit.new();custom.world=w
	check(kernel.new_visible([custom],GameUnit,u,w,w.ai,PackedFloat64Array(),{},{},15.0)==null,"custom target falls back to ordered script loop")
	custom.free()
	adapter(kernel)
	for target in rows:target.free()
	u.free();w.free()
	print("PERCEPTION_BATCH checks=",checks," failures=",failures," native_us=",native_us," script_us=",script_us)
	get_tree().quit(1 if failures else 0)
