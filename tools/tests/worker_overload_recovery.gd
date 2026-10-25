extends Node
## Sustained single-digit authority FPS, then normal frames/rate changes.
## A finite per-callback tick count alone does not bound accumulated backlog.
class ClockWorld extends GameWorld:
	func _tick_body(dt: float) -> void:
		time += dt

var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 15: printerr("FAIL ",label)

func _ready() -> void:
	for worker in [false,true]:
		for stalled_rate in [1.0,2.0,55.0/27.0]:
			for recovery_rate in [1.0,2.0,55.0/27.0]:
				var w := ClockWorld.new()
				w.retain_logic_debt=worker
				var now := 1000
				w._sample_frame(now,stalled_rate)
				for gap in [125,200,500,1000,2000,500,1000,500,1000,500]:
					now+=gap; w._sample_frame(now,stalled_rate)
					check(w._logic_debt < GameWorld.TICK,"sustained overload has no whole-tick backlog")
					check(w.logic_fraction()>=0.0 and w.logic_fraction()<1.0,"overload interpolation remains fractional")
				var before := w.time
				var fractional := w._logic_accumulator
				for frame in 90:
					var previous := w._logic_step
					now+=33; w._sample_frame(now,recovery_rate)
					check(w._logic_step-previous <= ceili(0.033*recovery_rate/GameWorld.TICK),"recovery does not fast-forward NPC ticks")
					check(absf(w.time-before-float(frame+1)*0.033*recovery_rate) <= GameWorld.TICK,"recovery follows current speed, including 2x to 1x")
				check(absf(w.time-before+w._logic_accumulator-fractional-2.97*recovery_rate)<1e-8,"healthy admitted time remains exact")
				w.free()
	print("WORKER_OVERLOAD_RECOVERY ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
