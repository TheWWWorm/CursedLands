extends "res://tools/tests/path_trace_traversal_stalls.gd"
## Correlate an instrumented engine's pipeline timings with real route phases.
## This fixture does not change the production scene or shader preparation.
func stage(label: String,seconds: float,predicate:=Callable()) -> void:
	print("PIPELINE_PHASE ",JSON.stringify({"phase":label,"event":"begin","at_us":Time.get_ticks_usec()}))
	await super.stage(label,seconds,predicate)
	print("PIPELINE_PHASE ",JSON.stringify({"phase":label,"event":"end","at_us":Time.get_ticks_usec()}))
