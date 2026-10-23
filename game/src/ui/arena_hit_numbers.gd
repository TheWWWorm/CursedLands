class_name ArenaHitNumbers
extends FlyingHP
## Same native hit events, atlas, labels and posed anchors as the campaign.
var field: ArenaField
func _draw() -> void:
	if _tex == null or field == null or field.match_state == null or not is_instance_valid(field.match_state.world): return
	if not GameData.option("show_flying_hp"): return
	var now := Time.get_ticks_msec()
	for item: Dictionary in _items:
		var unit: GameUnit = field.match_state.world.units.get(int(item.uid))
		if not is_instance_valid(unit) or not unit.visible or unit.hidden or unit.model == null: continue
		var at: Variant = _anchor(unit, field.camera)
		if at == null: continue
		for glyph: Dictionary in readable_layout(at, int(item.n), int(item.f), unit.faction == 1, now - int(item.t0), field.size):
			draw_texture_rect_region(_tex, glyph.rect, glyph.source, glyph.colour)
	_items = _items.filter(func(item): return (int(item.f) & 0x80000000) == 0)
