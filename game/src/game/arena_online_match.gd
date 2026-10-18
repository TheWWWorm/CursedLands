class_name ArenaOnlineMatch
extends ArenaPveMatch
## Presentation only. Native movement, damage and outcomes arrive from the host.

func _ready() -> void:
	drives_clock = false
	super._ready()
	is_host = false

func prepare() -> void:
	if not is_instance_valid(world):
		formation.clear()
		_rebuild_world()
		is_host = false
		world.authority = false
		world.set_meta("expedition_spell_safety", true)

func _process(dt: float) -> void:
	_update_death_marks(dt)
	if phase == Phase.FINISHED:
		_finish_effects(dt)
		settle_remaining = maxf(0.0, settle_remaining - dt)

func _physics_process(dt: float) -> void:
	if rendered and phase == Phase.DEPLOY and is_instance_valid(world):
		formation_motion.advance(dt / maxf(Engine.time_scale, 0.001), world)
func start() -> bool: return false
func toggle_pause() -> void: pass
func set_speed(_value: float) -> void: pass
