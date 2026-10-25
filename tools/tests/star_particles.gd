extends Node
## Native ordered updates versus the original complete script path. Spawning
## deliberately remains the same scene/ground-aware callback in both modes.
class BoundsFx extends ParticleFx:
	func carrier_size(_obj: Object) -> Vector2:
		return Vector2(1.2,1.6)

class TestGround extends FxGround:
	func at(x: float, y: float) -> float:
		return sin(x*0.7)+y*0.13

class CustomEmitter extends FxEmitter:
	func rnd() -> int: return 7

class Probe extends RefCounted:
	var calls := 0
	func advance(_e: Object) -> bool:
		calls+=1
		return false # Explicit native decline must fall back without mutation.

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		if failures<12: printerr("FAIL ",label)

func compare(a: FxEmitter, b: FxEmitter, label: String) -> void:
	check(a.parts==b.parts,label+" complete interpolation records")
	if a.parts!=b.parts and failures<4:
		for i in mini(a.parts.size(),b.parts.size()):
			if a.parts[i]!=b.parts[i]:
				printerr("ROW ",i," native=",a.parts[i]," script=",b.parts[i])
				for field in 25:
					if a.parts[i][field]!=b.parts[i][field]:printerr("FIELD ",field," native64=",PackedFloat64Array([a.parts[i][field]]).to_byte_array().hex_encode()," script64=",PackedFloat64Array([b.parts[i][field]]).to_byte_array().hex_encode())
				break
	check(a.rng.state==b.rng.state,label+" future random stream")
	check(a.flags==b.flags and a.d0==b.d0 and a.has_carrier==b.has_carrier and a.ofs==b.ofs,label+" emission and attachment state")

func _ready() -> void:
	check(ClassDB.class_exists("StarParticleKernel"),"native star updates are available")
	if failures: finish();return
	var fa := BoundsFx.new();var fb := BoundsFx.new()
	var random := RandomNumberGenerator.new();random.seed=947216
	for kind in [0x2038,0x204d]:
		for trial in 24:
			var a := FxTypes.create(fa,kind);var b := FxTypes.create(fb,kind)
			check(a.get("_star_kernel")!=null,"factory selects native stars")
			check(a.par==(kind==0x2038),"carrier-dependent wisps retain main-thread ownership")
			a.rng.seed=123947+trial;b.rng.seed=a.rng.seed
			var values := {"d0":trial%9,"d8":[1,12,57,250][trial%4],"d4":[0.0,0.03,0.8,1000.0][trial%4],
				"cc":[-1,0,40,51,88,100][trial%6],"s":random.randf_range(0.02,9.0),
				"ground_src":TestGround.new(),"k118":random.randf_range(1,8),"k11c":random.randf_range(1,8),
				"k120":cos(trial*0.47),"k124":sin(trial*0.47),"v130":Vector3(trial%2,0,0)}
			for key in values:a.set(key,values[key]);b.set(key,values[key])
			# Existing old-dead, newly-dead, out-of-table and interleaved rows.
			for i in 7:
				var p := FxEmitter.new_particle();p[0]=float(i);p[2]=3.25;p[3]=0.7
				p[0x11]=i*5;p[0x14]=[-1,0,1,5,15,20,100][i];p[0x18]=int(i==3);p[0x16]=0x517e2c33
				p[8]=0.9;p[0xb]=0.08;a.push(p);b.push(p.duplicate(true))
			var ua := GameUnit.new();var ub := GameUnit.new()
			for tick in 90:
				for emitter in [a,b]:
					emitter.wp=Vector3(100+tick*0.06,-40+trial*0.2,7)
					emitter.moved=float(tick%4)*0.06
					emitter.flags=(1|(2 if trial%2 else 0)|(4 if trial%3 else 0)) if tick<60 else (4 if trial%3 else 0)
				ua.gait_run=tick%8>3;ub.gait_run=ua.gait_run;ua.dead=tick==44;ub.dead=ua.dead
				a.attach(ua if tick%7!=0 else null);b.attach(ub if tick%7!=0 else null)
				check(a.update_sim()==b.update_sim_script(),"emitter lifetime")
				compare(a,b,"%s/%s/%s"%[kind,trial,tick])
			ua.free();ub.free()
	# Production dispatch, declined native work and optional older libraries.
	var a := FxTypes.create(fa,0x2038);var b := FxTypes.create(fb,0x2038)
	a.rng.seed=1903;b.rng.seed=a.rng.seed
	var probe := Probe.new();a.set("_star_kernel",probe)
	a.update_sim();b.update_sim_script()
	check(probe.calls==1,"production update makes one native call")
	compare(a,b,"declined helper")
	a.set("_star_kernel",null);a.update_sim();b.update_sim_script();compare(a,b,"missing library")
	var custom := CustomEmitter.new();custom.type=0x204d;custom.call("prepare_star_batch")
	check(custom.get("_star_kernel")==null,"subclass random and lifecycle overrides keep script path")
	for changed in ["spawn","update","control","type"]:
		a=FxTypes.create(fa,0x2038);b=FxTypes.create(fb,0x2038)
		a.rng.seed=541;b.rng.seed=a.rng.seed;a.update_sim();b.update_sim_script()
		probe=Probe.new();a.set("_star_kernel",probe)
		for e in [a,b]:
			match changed:
				"spawn": e.spawn_fn=func(_e:FxEmitter,p:Array,_i:int)->bool:p[3]=123.0;return true
				"update": e.upd_fn=func(_e:FxEmitter,p:Array)->bool:p[2]+=23.0;return true
				"control": e.cp=[FxEmitter.new_control()];e.ctl_fn=func(em:FxEmitter,_p:Array)->void:em.d0=0;em.cc=0
				"type": e.type=0x204d
		a.update_sim();b.update_sim_script()
		check(probe.calls==0,"changed "+changed+" retains custom script callbacks")
		compare(a,b,"changed "+changed)
	# Exit workers keep separate arrays and RNG streams; wisps remain serial.
	var jobs := []
	for i in 24:
		a=FxTypes.create(fa,0x2038);b=FxTypes.create(fb,0x2038)
		a.rng.seed=600+i;b.rng.seed=a.rng.seed
		a.ground_src=TestGround.new();b.ground_src=a.ground_src
		jobs.append([a,b])
	var task := WorkerThreadPool.add_group_task(func(i:int)->void:
		for tick in 40:
			jobs[i][0].update_sim();jobs[i][1].update_sim_script()
	,jobs.size(),4)
	WorkerThreadPool.wait_for_group_task_completion(task)
	for pair in jobs:compare(pair[0],pair[1],"independent worker")
	var timing := []
	for kind in [0x2038,0x204d]:
		for fast in [false,true,true,false]:
			var e := FxTypes.create(fa,kind);e.rng.seed=1905;e.s=0.05
			var u := GameUnit.new();e.attach(u)
			for tick in 30:e.update_sim_script()
			var started := Time.get_ticks_usec()
			for tick in 600:
				if fast:e.update_sim()
				else:e.update_sim_script()
			timing.append({"kind":kind,"native":fast,"ticks":600,"usec":Time.get_ticks_usec()-started,"particles":e.parts.size(),"rng_state":e.rng.state})
			u.free()
	print("STAR_PARTICLES_TIMING ",JSON.stringify(timing))
	fa.free();fb.free();finish()

func finish() -> void:
	print("STAR_PARTICLES checks=",checks," failures=",failures)
	get_tree().quit(int(failures>0))
