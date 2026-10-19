class_name ArenaRoundBanner
extends VBoxContainer
## A short, unframed notice in the top HUD. Result delivery never delays combat.
const RESULT_SECONDS := 2.0
var heading: Label
var detail: Label
var countdown: Label
var _key := ""
var _age := 0.0
var _duration := 0.0
var _kind := ""
var _pending := {}
var _session := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)
	for item in ["heading", "detail", "countdown"]:
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 34 if item == "heading" else 15)
		label.add_theme_color_override("font_color", ArenaCreatureCard.PAPER)
		ArenaCreatureCard.outline(label)
		label.add_theme_constant_override("outline_size", 6 if item == "heading" else 3)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		label.add_theme_constant_override("shadow_offset_y", 2)
		if item == "heading":
			label.add_theme_font_override("font", preload("res://fonts/LiberationSans-Bold.ttf"))
			heading = label
		elif item == "detail":
			detail = label
			detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		else: countdown = label; label.hide()
		add_child(label)
	hide()

func update_round(run: ArenaRun, dt: float, _result_left: float, covered: bool) -> void:
	var session := "%d:%d" % [run.get_instance_id(), run.run_seed]
	if session != _session:
		_session = session; _key = ""; _pending.clear(); _duration = 0.0
	_age += maxf(0.0, dt)
	var resolved := (run.stage == "fight" and int(run.last_result.get("wave", -1)) == run.wave) or run.stage in ["result", "won", "lost"]
	var kind := "result" if resolved else run.stage
	var key := "%d:%s" % [run.wave, kind]
	if key != _key:
		_key = key
		var event := {"kind":kind, "title":run.round_title(), "detail":"", "duration":2.6, "color":Color("ffe3a1")}
		if resolved:
			var winner := int(run.last_result.get("winner", -1))
			event.title = RemakeText.t("Victory" if winner == 0 else "Draw" if winner < 0 else "Defeat")
			event.color = Color("ffe3a1") if winner == 0 else Color("ff9a8d")
			event.duration = RESULT_SECONDS
			var loss := int(run.last_result.get("health_lost", 0))
			if loss > 0: event.detail = RemakeText.t("%d health lost") % loss
		elif kind == "fight":
			event.detail = RemakeText.t("Battle begins")
			event.duration = 1.0
		elif kind == "prepare":
			event.detail = income_text(run.last_result.get("income", {}))
		else: event.duration = 0.0
		# A short opening battle must not replace the start title on the same
		# frame. Keep it steady for a second, then show the result once.
		if resolved and _kind == "fight" and _age < 1.0:
			_pending = event
		else:
			_pending.clear()
			_present(event)
	if not _pending.is_empty() and _age >= 1.0:
		_present(_pending)
		_pending = {}
	visible = not covered and _age < _duration
	modulate.a = clampf((_duration - _age) / 0.25, 0.0, 1.0)

func _present(event: Dictionary) -> void:
	_kind = event.kind; _age = 0.0; _duration = event.duration
	heading.text = event.title
	heading.add_theme_color_override("font_color", event.color)
	detail.text = event.detail
	detail.visible = not detail.text.is_empty()

static func income_text(income: Dictionary) -> String:
	if income.is_empty(): return ""
	var parts: Array[String] = []
	var keys := {"base":"+%d base gold", "interest":"+%d interest", "victory":"+%d victory", "streak":"+%d streak"}
	for key: String in keys:
		if int(income.get(key, 0)) > 0: parts.append(RemakeText.t(keys[key]) % int(income[key]))
	return "   ".join(parts) + "\n" + RemakeText.t("%d total gold") % int(income.get("total", 0))
