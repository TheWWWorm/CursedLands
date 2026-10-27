extends Node
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)
func _ready() -> void:
	var facts := {"engine":true,"api":true,"launch":true,"sr":true,"fg":false,"reflex":true,"runtime_error":true}
	var message := "Frame generation stopped after a runtime error. Restart the game to retry."
	check(RtxGraphics.reason_for(RtxGraphics.FRAME_GENERATION,facts,4) == message,"reported SDK error is distinguished from unsupported hardware")
	check(RtxGraphics.reason_for(RtxGraphics.UPSCALING,facts,4).is_empty(),"FG failure does not claim the working DLSS upscaler failed")
	facts.runtime_error = false
	check(RtxGraphics.reason_for(RtxGraphics.FRAME_GENERATION,facts,4) == RtxGraphics.NEED_FG,"unsupported hardware retains its own explanation")
	facts.runtime_error = true; facts.sr = false
	var sr := "DLSS stopped after a runtime error. Restart the game to retry."
	check(RtxGraphics.reason_for(RtxGraphics.UPSCALING,facts,4) == sr,"upscaler runtime failure is also explicit")
	for language in ["ru","de"]:
		RemakeText.lang = language
		check(RemakeText.t(message) != message and RemakeText.t(sr) != sr,"runtime recovery messages translated into " + language)
	print("RTX_RUNTIME_FAILURE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
