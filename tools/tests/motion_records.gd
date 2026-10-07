extends Node
## Identical route construction, independent scalar/native evaluators. Include
## exact interval boundaries, backward seeks, standing turns and blocked rates.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 20: printerr("FAIL ",label)

func compare(m: NavSpline, at: float) -> void:
	var a := m.sample(at)
	var b := m.sample_script(at)
	check(a == b,"native sample equals scalar at %s: %s / %s" % [at,a,b])

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 840116
	var m := NavSpline.new()
	check(m._kernel != null,"native motion records available")
	for trial in 100:
		var cells: Array[Vector2i] = []
		var values := PackedInt32Array()
		var p := Vector2i(20,20)
		for i in 1+trial%31:
			cells.append(p); values.append(rng.randi_range(100,900))
			p += [Vector2i(1,0),Vector2i(1,1),Vector2i(0,1)][rng.randi_range(0,2)]
		var from := Vector2(cells[0])*0.5+Vector2(0.1,0.2)
		var to := Vector2(cells[-1])*0.5+Vector2(0.3,0.4)
		var base := rng.randf_range(0.01,1.0) if trial%7 else 0.0
		var turn := rng.randf_range(0.01,0.8) if trial%9 else 0.0
		m.build(from,to,cells,values,base,turn,rng.randf_range(-PI,PI))
		for at in [-1.0,0.0,0.000001,1.0,20.0,1000.0]: compare(m,at)
		var boundary := absf(m.initial_turn)/turn if turn > 0.0 else 0.0
		if turn > 0.0:
			for interval in m._intervals:
				if not is_finite(boundary): break
				for offset in [-0.00000001,0.0,0.00000001]: compare(m,boundary+offset)
				boundary += interval
		if is_finite(m.duration):
			for at in [m.duration,m.duration+0.001,m.duration*0.5]: compare(m,at)
			for i in 80: compare(m,rng.randf_range(0.0,m.duration+0.1))
		# Rebuilding the same object must replace its previous owned records.
		m.build(from,to,[],PackedInt32Array(),base,turn,0.4)
		compare(m,0.0); compare(m,100.0)
	print("MOTION_RECORDS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
