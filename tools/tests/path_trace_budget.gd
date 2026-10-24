extends Node
const Budget = preload("res://src/game/fx/path_trace_budget.gd")
var checks := 0
var failures := []
var frame := 0
func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func feed(b: RefCounted,count: int,gpu: float,pt: float,dt := 1.0/60.0,blocked := false) -> void:
	for i in count:
		frame+=1;b.observe(frame,dt,gpu,pt,blocked)
func _ready() -> void:
	var b := Budget.new();b.configure(3)
	feed(b,600,15.0,8.0)
	check(b.scale==1.0,"GPU work within budget retains selected quality")
	feed(b,1,100.0,80.0,0.7);feed(b,180,15.0,8.0)
	check(b.scale==1.0,"a long CPU/loading stall cannot reduce quality")
	feed(b,600,28.0,20.0,1.0/60.0,true)
	check(b.scale==1.0,"paused or rebuilding frames cannot reduce quality")
	feed(b,180,28.0,20.0)
	check(b.scale<1.0 and b.scale>=0.9,"sustained GPU load lowers quality in small steps")
	var changes := b.changes;var scale := b.scale
	feed(b,360,16.0,8.0)
	check(b.scale==scale and b.changes==changes,"near-target work holds its quality without oscillation")
	feed(b,180,9.0,5.0)
	check(b.scale==scale,"brief headroom does not raise quality")
	feed(b,240,9.0,5.0)
	check(b.scale>scale and b.scale<=1.0,"sustained headroom restores quality gradually")
	feed(b,2400,50.0,35.0)
	check(is_equal_approx(b.scale,Budget.MIN_SCALE),"adaptive quality has a fixed lower bound")
	var pixels := b.size(Vector2i(1280,720))
	check(pixels.x<=1280 and pixels.y<=720 and absf(float(pixels.x)/pixels.y-16.0/9.0)<0.01,"adaptive lattice preserves aspect and selected quality ceiling")
	var old := b.scale
	for i in 1000:b.observe(frame,1.0/60.0,9.0,5.0,false)
	check(b.scale==old,"duplicate GPU timestamps and generated display frames cannot train the controller")
	b.configure(0);feed(b,600,90.0,70.0)
	check(b.scale==1.0 and b.size(Vector2i(1280,720))==Vector2i(1280,720),"Off restores exact manual quality")
	print("PATH_TRACE_BUDGET ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
