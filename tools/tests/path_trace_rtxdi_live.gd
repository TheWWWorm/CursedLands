extends "res://tools/tests/path_trace_rr_live.gd"
## Execute the complete native RR contract with actual RTXDI enabled.
func run() -> void:
	GameData.options.pt_restir=1
	await super.run()
func record_rr(rt: Node,label: String) -> void:
	await super.record_rr(rt,label)
	check(rt.device._rtxdi_mode and rt.device.rtxdi.frames>0 and not rt.device.rtxdi_failed,"actual RTXDI remains active through "+label)
