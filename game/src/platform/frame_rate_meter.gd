class_name FrameRateMeter
extends RefCounted
## Presentation counters include generated frames; engine FPS does not.
## Measure both counters over the same wall-clock interval. Never infer x2.

var _samples: Array[Dictionary] = []

func sample(status: Dictionary, now_usec: int, engine_fps: float) -> Dictionary:
	var result := {"rendered_fps": engine_fps, "presented_fps": -1.0,
		"frame_generation_active": bool(status.get("frame_generation_active", false))}
	if not result.frame_generation_active or not status.get("present_count_available", false):
		_samples.clear()
		return result
	if not status.has("presented_frames") or not status.has("game_presents"):
		_samples.clear()
		return result
	var current := {"time": now_usec, "presented": int(status.presented_frames), "rendered": int(status.game_presents)}
	if not _samples.is_empty():
		var last: Dictionary = _samples.back()
		if now_usec <= int(last.time) or now_usec - int(last.time) > 2_000_000 or current.presented < last.presented or current.rendered < last.rendered:
			_samples.clear()
	_samples.append(current)
	while _samples.size() > 2 and int(_samples[1].time) <= now_usec - 1_000_000:
		_samples.pop_front()
	var first: Dictionary = _samples.front()
	var elapsed := (now_usec - int(first.time)) / 1_000_000.0
	if elapsed >= 0.5:
		result.rendered_fps = (current.rendered - first.rendered) / elapsed
		result.presented_fps = (current.presented - first.presented) / elapsed
	return result

static func label_text(rates: Dictionary) -> String:
	if not rates.get("frame_generation_active", false):
		return "%d FPS" % roundi(rates.rendered_fps)
	var presented := RemakeText.t("%d FPS presented") % roundi(rates.presented_fps) if rates.presented_fps >= 0 else RemakeText.t("Presented FPS: …")
	return (RemakeText.t("%d FPS rendered") % roundi(rates.rendered_fps)) + "\n" + presented
