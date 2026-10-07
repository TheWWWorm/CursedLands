extends Node
var checks := 0
var failures := 0
var kernel: Object

class DecodeJob extends RefCounted:
	var kernel: Object
	var bytes: PackedByteArray
	var expected: PackedByteArray
	var align := 256
	var channels := 2
	var ok := true
	func run() -> void:
		for i in 100:
			if kernel.decode_ima(bytes,align,channels) != expected: ok = false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 12: printerr("FAIL ",label)

func run_job(i: int, jobs: Array) -> void:
	jobs[i].run()

func _ready() -> void:
	check(ClassDB.class_exists("AudioDecodeKernel"),"compiled audio decoder is present")
	if failures:
		get_tree().quit(1)
		return
	kernel = ClassDB.instantiate("AudioDecodeKernel")
	EIAudio._tables()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9238561
	# Every nibble and step index, with both saturation limits and zero.
	for index in 89:
		for predictor in [-32768,0,32767]:
			var data := PackedByteArray()
			data.resize(20)
			data.encode_s16(0,predictor)
			data[2] = index
			for nibble in 16: data[4+nibble] = nibble | nibble << 4
			check(kernel.decode_ima(data,20,1) == EIAudio._ima_decode_script(data,20,1),"nibbles/index/predictor")
	var jobs: Array = []
	for trial in 300:
		var channels := rng.randi_range(1,8)
		var align := channels * 4 + rng.randi_range(1,280)
		var data := PackedByteArray()
		data.resize(rng.randi_range(0,align*5+3))
		for i in data.size(): data[i] = rng.randi() & 255
		var expected := EIAudio._ima_decode_script(data,align,channels)
		check(kernel.decode_ima(data,align,channels) == expected,"partial/random blocks %d" % trial)
		if trial < 16:
			var job := DecodeJob.new()
			job.kernel = kernel; job.bytes = data; job.expected = expected
			job.align = align; job.channels = channels
			jobs.append(job)
	for args in [[0,0],[5,0],[5,-1],[36,9],[-1,1],[4,1],[8,2],[2147483648,1]]:
		check((kernel.decode_ima(PackedByteArray([0,0,0,0]),args[0],args[1]) as PackedByteArray).is_empty(),"invalid format")
	jobs.make_read_only()
	var group := WorkerThreadPool.add_group_task(run_job.bind(jobs),jobs.size(),4,false,"audio decoder check")
	WorkerThreadPool.wait_for_group_task_completion(group)
	for job: DecodeJob in jobs: check(job.ok,"concurrent immutable decoder")
	# Decode every authored IMA sound, independently of the stream cache.
	var archive := EIAudio._archive("sfx.res")
	var assets := 0
	var native_us := 0
	var script_us := 0
	for name in archive.names_with_suffix(".wav"):
		var bytes := archive.read(name)
		if bytes.size() < 44 or bytes.slice(0,4).get_string_from_ascii() != "RIFF": continue
		var format := 0
		var channels := 0
		var align := 0
		var data := PackedByteArray()
		var pos := 12
		while pos + 8 <= bytes.size():
			var chunk := bytes.slice(pos,pos+4).get_string_from_ascii()
			var size := bytes.decode_u32(pos+4)
			if chunk == "fmt " and size >= 16 and pos+24 <= bytes.size():
				format = bytes.decode_u16(pos+8); channels = bytes.decode_u16(pos+10); align = bytes.decode_u16(pos+20)
			elif chunk == "data": data = bytes.slice(pos+8,mini(bytes.size(),pos+8+size))
			pos += 8+size+(size&1)
		if format != 17: continue
		var start := Time.get_ticks_usec()
		var native: PackedByteArray = kernel.decode_ima(data,align,channels)
		native_us += Time.get_ticks_usec()-start
		start = Time.get_ticks_usec()
		var expected := EIAudio._ima_decode_script(data,align,channels)
		script_us += Time.get_ticks_usec()-start
		check(native == expected,"asset "+name)
		check(EIAudio.decode_wav(bytes).data == expected,"stream integration "+name)
		assets += 1
	check(assets > 0,"authored IMA assets were exercised")
	print("AUDIO_NATIVE ",JSON.stringify({"checks":checks,"failures":failures,"assets":assets,"native_us":native_us,"script_us":script_us}))
	get_tree().quit(1 if failures else 0)
