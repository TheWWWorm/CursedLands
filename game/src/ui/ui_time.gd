class_name UiTime
## Real time for the interface. The game speed option speeds up only the
## original's server tick; the cursor, panels, portraits and other interface
## animations keep their real-time (timeGetTime) pace. The remake's game speed
## is Engine.time_scale, which scales every node's delta, so an interface
## timer converts its delta back to real seconds here.


## The real seconds behind a frame delta `dt` scaled by the game speed.
static func real(dt: float) -> float:
	return dt / maxf(Engine.time_scale, 0.001)
