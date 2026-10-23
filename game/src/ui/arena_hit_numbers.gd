class_name ArenaHitNumbers
extends FlyingHP
## Same native hit events, atlas, labels and posed anchors as the campaign.
var field: ArenaField
const EFFECT_NAMES := {
	"fang": "Life stolen", "storm": "Chain lightning", "venom": "Healing reduced",
	"ward": "Ward shield", "guardian": "Ally shield", "echo": "Spell echo", "thorn": "Thorns",
	"pack": "Pack strike", "rally": "Horde rally", "guard": "Guarded", "marked": "Marked caster",
	"reaction": "Spell reaction", "spirit": "Spirit aid", "spirit_echo": "Spirit echo",
}
var _procs: Array[Dictionary] = []

func add_proc(event: Dictionary) -> void:
	if not EFFECT_NAMES.has(String(event.get("effect", ""))): return
	if field == null or field.match_state == null: return
	var w: GameWorld = field.match_state.world
	if not is_instance_valid(w): return
	# One short notice per actor, at most twelve on the viewed board.
	_procs = _procs.filter(func(p): return p.world == w.get_instance_id() and int(p.uid) != int(event.uid))
	_procs.append({"uid": int(event.uid), "effect": String(event.effect), "at": w.time, "world": w.get_instance_id()})
	while _procs.size() > 12: _procs.pop_front()

func _draw_procs() -> void:
	var w: GameWorld = field.match_state.world
	if field.match_state.phase == ArenaMatch.Phase.FINISHED:
		_procs.clear()
		return
	_procs = _procs.filter(func(p): return p.world == w.get_instance_id() and w.time - float(p.at) < 1.5)
	var font := get_theme_default_font()
	var occupied: Array[Rect2] = []
	for unit: GameUnit in w.unit_rows():
		if unit.dead or not unit.visible or unit.hidden or field.camera.is_position_behind(unit.global_position): continue
		occupied.append(Rect2(field.health_anchor(unit) + Vector2(-48, -40) * field.ui_scale, Vector2(96, 46) * field.ui_scale))
	for notice in _procs:
		var unit: GameUnit = w.units.get(int(notice.uid))
		if not is_instance_valid(unit) or not unit.visible or unit.hidden or unit.model == null: continue
		if field.camera.is_position_behind(unit.global_position): continue
		var anchor: Vector2 = field.health_anchor(unit)
		var label := RemakeText.t(EFFECT_NAMES[notice.effect])
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 16.0
		var pos: Vector2 = anchor + Vector2(-width * 0.5, -65.0 * field.ui_scale - (w.time - float(notice.at)) * 8.0)
		pos.x = clampf(pos.x, 4.0, maxf(4.0, field.size.x - width - 4.0))
		var box := Rect2(pos, Vector2(width, 23))
		for attempt in occupied.size() + 1:
			var lifted := false
			for previous: Rect2 in occupied:
				if box.intersects(previous):
					box.position.y = previous.position.y - box.size.y - 2.0
					lifted = true
			if not lifted: break
		if box.position.y < 4.0: continue
		occupied.append(box)
		var fade := clampf((1.5 - (w.time - float(notice.at))) * 3.0, 0.0, 1.0)
		draw_rect(box, Color(0.07, 0.09, 0.1, 0.85 * fade))
		draw_string(font, box.position + Vector2(8, 17), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.86, 0.55, fade))

func _draw() -> void:
	if _tex == null or field == null or field.match_state == null or not is_instance_valid(field.match_state.world): return
	if not GameData.option("show_flying_hp"): return
	_draw_procs()
	var now := Time.get_ticks_msec()
	for item: Dictionary in _items:
		var unit: GameUnit = field.match_state.world.units.get(int(item.uid))
		if not is_instance_valid(unit) or not unit.visible or unit.hidden or unit.model == null: continue
		var at: Variant = _anchor(unit, field.camera)
		if at == null: continue
		for glyph: Dictionary in readable_layout(at, int(item.n), int(item.f), unit.faction == 1, now - int(item.t0), field.size):
			draw_texture_rect_region(_tex, glyph.rect, glyph.source, glyph.colour)
	_items = _items.filter(func(item): return (int(item.f) & 0x80000000) == 0)
