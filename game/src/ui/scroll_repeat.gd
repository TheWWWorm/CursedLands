extends RefCounted
## Shared mouse/touch arrow repeat. Real UI seconds, independent of game speed.
var key := ""
var direction := 0
var elapsed := 0.0
var due := 0.4

func begin(which: String, step: int) -> void:
	key = which
	direction = step
	elapsed = 0.0
	due = 0.4

func stop() -> void:
	key = ""
	direction = 0

func advance(dt: float) -> int:
	if key.is_empty(): return 0
	elapsed += maxf(0.0, dt)
	var steps := 0
	while elapsed >= due:
		steps += 1
		due += lerpf(0.18, 0.055, clampf((elapsed - 0.4) / 1.6, 0.0, 1.0))
		if steps >= 32: # Never replay an entire suspended application's backlog.
			due = elapsed + 0.055
			break
	return steps * direction
