class_name ArenaEvolutionNotice
extends ArenaHudPanel
## Brief, nonmodal before/after feedback. Events are queued, not written to a log.

signal shown(event: Dictionary)
const DURATION := 3.4
var current := {}
var pending: Array[Dictionary] = []
var age := 0.0
var covered := false
var _content: VBoxContainer


func _ready() -> void:
	super._ready()
	surface.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = 292
	minimum_size_changed.connect(_layout.call_deferred)
	get_parent().resized.connect(_layout)
	hide()


func present(events: Array[Dictionary]) -> void:
	for event in events: pending.append(event.duplicate(true))
	if current.is_empty(): _next()


func clear() -> void:
	pending.clear()
	current.clear()
	if is_instance_valid(_content):
		remove_child(_content)
		_content.queue_free()
	_content = null
	hide()


func retain(run: ArenaRun) -> void:
	pending = pending.filter(func(event): return _still_owned(event, run))
	if not current.is_empty() and not _still_owned(current, run): _next()


func _still_owned(event: Dictionary, run: ArenaRun) -> bool:
	return run.pact_prototype() == event.to if int(event.uid) == 0 else run.unit(event.uid).get("prototype", "") == event.to


func _next() -> void:
	var remaining := pending.duplicate(true)
	clear()
	pending.assign(remaining)
	if pending.is_empty(): return
	current = pending.pop_front()
	age = 0
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	add_child(_content)
	var heading := _label(_content, RemakeText.t("Evolved"), 20, ArenaCreatureCard.GOLD)
	heading.add_theme_font_override("font", preload("res://fonts/LiberationSerif-Regular.ttf"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_content.add_child(row)
	_figure(row, current.from, int(current.old_rank))
	var arrow := _label(row, "→", 24, ArenaCreatureCard.GOLD)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_figure(row, current.to, int(current.rank), true)
	var before := ArenaUnitInfo.values(current.from)
	var after := ArenaUnitInfo.values(current.to)
	var stats := _label(_content, RemakeText.t("Health %d → %d · Attack %d → %d") % [before.max_hp, after.max_hp, before.attack, after.attack], 14, ArenaCreatureCard.PAPER)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for control: Control in find_children("*", "Control", true, false): control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0
	show()
	_layout.call_deferred()
	shown.emit(current)


func _figure(parent: Control, id: String, rank: int, upgraded := false) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	parent.add_child(box)
	var center := CenterContainer.new()
	box.add_child(center)
	ArenaStars.add_to(center, rank + 1, Vector2.ZERO)
	var preview := WikiPreview.new()
	preview.fit_slot = true
	preview.custom_minimum_size = Vector2(100, 66)
	box.add_child(preview)
	preview.show_model({"kind": "creature", "value": id})
	preview.turn_by(-0.35)
	var label := _label(box, ArenaRules.title(id), 16, ArenaCreatureCard.GOLD if upgraded else ArenaCreatureCard.MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.y = 44


func _label(parent: Node, value: String, pixels: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _layout() -> void:
	size = Vector2(292, 0)
	position = Vector2(get_parent().size.x - size.x - 16, 158)


func _process(dt: float) -> void:
	if not visible: return
	if covered:
		modulate.a = 0
		return
	age += dt
	modulate.a = minf(clampf(age / 0.16, 0, 1), clampf((DURATION - age) / 0.4, 0, 1))
	if age >= DURATION: _next()
