extends "fire_particles.gd"
## Includes original scene-dependent initialization, then exact batched ticks.
func _ready() -> void:
	check(ClassDB.class_exists("SpellParticleKernel"), "native spell batches available")
	if failures: get_tree().quit(1); return
	var fa := ParticleFx.new(); var fb := ParticleFx.new()
	var carrier := Node3D.new()
	var random := RandomNumberGenerator.new(); random.seed = 817496
	var kinds := range(0x201b, 0x2027) + range(0x202b, 0x202f)
	var native_us := 0; var script_us := 0; var native_ticks := 0
	for kind in kinds:
		for trial in 12:
			var a := FxTypes.create(fa, kind); var b := FxTypes.create(fb, kind)
			b.rng.seed = a.rng.seed
			check(a._spell_kernel != null, "factory selects spell batch")
			var values := {"carrier":carrier,"has_carrier":true,"s":[-3.4,-1.0,1.0,4.1][trial % 4],
				"cc":[0,40,51,88,100,100][trial % 6],"d0":[1,8,80][trial % 3],
				"d8":[8,51,500][trial % 3],"d4":[0.0,0.07,1000.0][trial % 3]}
			for key in values: a.set(key,values[key]); b.set(key,values[key])
			for tick in 80:
				var wp := Vector3(random.randf_range(-400,400),random.randf_range(-400,400),random.randf_range(-20,90))
				a.wp=wp; b.wp=wp; a.moved=tick % 4 * 0.06; b.moved=a.moved
				if tick == 30: a.stop(); b.stop()
				if tick == 40: a.attach(null); b.attach(null)
				if tick == 55:
					a.attach(carrier); b.attach(carrier); a.flags |= FxEmitter.F_EMIT; b.flags=a.flags
				if not a.cp.is_empty() and (a.type < 0x202b or a.cp.size() >= a.ec): native_ticks += 1
				var start := Time.get_ticks_usec(); var alive_a := a.update_sim(); native_us += Time.get_ticks_usec()-start
				start=Time.get_ticks_usec(); var alive_b := b.update_sim_script(); script_us += Time.get_ticks_usec()-start
				var label := "%x/%d/%d" % [kind,trial,tick]
				check(alive_a == alive_b,label+" lifetime")
				compare(a,b,label)
				check(a.cp == b.cp,label+" controls")
				check(a.flags == b.flags,label+" flags")
	# A changed callback must bypass the native implementation.
	var custom := FxTypes.create(fa,0x202b)
	custom.attach(carrier); custom.update_sim()
	custom.ctl_fn = func(_e: FxEmitter, c: Array) -> void: c[0]=123.0
	custom.update_sim()
	check(custom.cp[0][0] == 123.0,"custom control fallback")
	check(native_ticks > 8000,"substantial native lifetime coverage")
	carrier.free(); fa.free(); fb.free()
	print("SPELL_PARTICLES checks=",checks," failures=",failures," native_ticks=",native_ticks," native_us=",native_us," script_us=",script_us)
	get_tree().quit(1 if failures else 0)
