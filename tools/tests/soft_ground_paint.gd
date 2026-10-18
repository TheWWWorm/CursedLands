extends Node
## Full-image parity for the optional CPU raster. Cover ordered overlaps,
## fading, sector boundaries, varying foot size, travel and invalid fallback.
var checks := 0
var failures := []
var samples := 0
var peak := 0.0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func _ready() -> void: run.call_deferred()
func run() -> void:
	check(ClassDB.class_exists("SoftGroundPaintKernel"), "native paint available")
	if not failures.is_empty(): get_tree().quit(1); return
	var kernel: Object = ClassDB.instantiate("SoftGroundPaintKernel")
	SoftGroundDeform._prepare_edge_noise()
	var random := RandomNumberGenerator.new(); random.seed=20261018
	var script_us := 0; var native_us := 0
	for trial in 6:
		var origin := Vector2(trial*32, -trial*32)
		var expected := Image.create(512,512,false,Image.FORMAT_RGBAF)
		expected.fill(Color(.15,.03,0,1))
		var actual := expected.duplicate() as Image
		var marks := []
		for index in 80:
			var local := Vector2(random.randf_range(-1,33),random.randf_range(-1,33))
			if index<8: local=Vector2(0 if index%2 else 32, index*4)
			var mark := {"p":local+origin,"extent":Vector2(random.randf_range(.025,.32),random.randf_range(.045,.46)),"angle":random.randf_range(-PI,PI),"time":float(trial*50+index*.2)}
			if index%2:
				mark.to=mark.p+Vector2(random.randf_range(-2.5,2.5),random.randf_range(-2.5,2.5))
				mark.extent=Vector2.ONE*random.randf_range(.18,.65)
				mark.pressure=random.randf_range(.35,1)
			marks.append(mark)
		# A late overlapping mark checks timestamp fade and max composition.
		var overlap: Dictionary=marks[13].duplicate(); overlap.time+=210.0;marks.append(overlap)
		var start := Time.get_ticks_usec()
		for mark: Dictionary in marks:
			if mark.has("to"): SoftGroundDeform.paint_trail(expected,mark.p-origin,mark.to-origin,mark.extent.x,mark.pressure,mark.time,origin)
			else: SoftGroundDeform.paint(expected,mark.p-origin,mark.extent,mark.angle,1.0,mark.time)
		script_us+=Time.get_ticks_usec()-start
		start=Time.get_ticks_usec()
		check(kernel.paint(actual,marks,origin,SoftGroundDeform._edge_noise),"accepted raster %d"%trial)
		native_us+=Time.get_ticks_usec()-start
		var a := actual.get_data().to_float32_array(); var e := expected.get_data().to_float32_array()
		var error := 0.0
		for index in a.size(): error=maxf(error,absf(a[index]-e[index]))
		samples+=a.size();peak=maxf(peak,error)
		check(error<0.000002,"all channels match %d (%.9f)"%[trial,error])
		var bytes := actual.get_data()
		check(not kernel.paint(actual,[marks[0],{"p":Vector2.ZERO}],origin,SoftGroundDeform._edge_noise),"invalid batch rejected")
		check(actual.get_data()==bytes,"rejection leaves image intact")
	var unsupported := Image.create(512,512,false,Image.FORMAT_RGBA8)
	check(not kernel.paint(unsupported,[],Vector2.ZERO,null),"unsupported format uses script")
	print("SOFT_GROUND_PAINT ",JSON.stringify({"checks":checks,"failures":failures,"samples":samples,"peak_error":peak,"script_us":script_us,"native_us":native_us}))
	get_tree().quit(1 if not failures.is_empty() else 0)
