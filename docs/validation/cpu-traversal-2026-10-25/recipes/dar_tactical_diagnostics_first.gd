extends "dar_tactical_metrics.gd"
## Diagnostic only: identify preparation owners without modifying the runtime.
var previous_owners := []
var previous_active := false
func _process(dt: float) -> void:
	super._process(dt)
	var active := ShaderCompilationScreen.active()
	var owners: Array = ShaderCompilationScreen._current._owners.keys() if active else []
	if active != previous_active or owners != previous_owners:
		print("DAR_PREPARATION ",JSON.stringify({"seconds":Time.get_ticks_usec()/1000000.0,"active":active,"owners":owners,"phase":ShaderCompilationScreen._current._phase if active else "","hero":str(hero.pos) if is_instance_valid(hero) else "loading"}))
		previous_owners=owners;previous_active=active
