class_name ArenaEvolutionPath
extends HBoxContainer
## Three native portraits connect an offer to the forms the player already owns.
var family := -1
var owned: Array[Dictionary] = []
var portrait_size := 36
var interactive := false
var _family := -2
var _counts: Array[Label] = []
var _ownership: Array[Label] = []
var _steps: Array[Control] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 2)

func update_path(value: int, army: Array[Dictionary]) -> void:
	family = value; owned = army
	if family < 0: hide(); return
	show()
	if _family != family:
		_family = family
		for child in get_children(): remove_child(child); child.queue_free()
		_counts.clear()
		_ownership.clear()
		_steps.clear()
		for rank in 3:
			if rank > 0:
				var arrow := Label.new(); arrow.text = "›"
				arrow.add_theme_font_size_override("font_size", 13)
				arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				ArenaCreatureCard.outline(arrow); add_child(arrow)
			var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 0)
			add_child(column)
			_steps.append(column)
			var image := Control.new()
			image.custom_minimum_size = Vector2.ONE * portrait_size
			column.add_child(image)
			var portrait := TextureRect.new()
			portrait.texture = ArenaPortraits.texture(ArenaRules.prototype(family, rank))
			portrait.custom_minimum_size = Vector2.ONE * portrait_size
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			image.add_child(portrait)
			portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var ownership := Label.new()
			ownership.add_theme_font_size_override("font_size", 12)
			ArenaCreatureCard.snow_ink(ownership, Color("9bfff0"))
			image.add_child(ownership)
			ownership.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			ownership.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			ownership.grow_vertical = Control.GROW_DIRECTION_BEGIN
			_ownership.append(ownership)
			var label := Label.new(); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 12)
			ArenaCreatureCard.snow_ink(label, ArenaStars.for_family(family))
			column.add_child(label); _counts.append(label)
		for child: Control in find_children("*", "Control", true, false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if interactive:
			for step: Control in _steps: step.mouse_filter = Control.MOUSE_FILTER_STOP
	for rank in 3:
		var count := owned.filter(func(entry): return int(entry.family) == family and int(entry.rank) == rank).size()
		_counts[rank].text = "★".repeat(rank + 1)
		_ownership[rank].visible = count > 0
		_ownership[rank].text = "✓" + (str(count) if count > 1 else "")
		_ownership[rank].set_meta("owned_count", count)
		_counts[rank].add_theme_color_override("font_color", ArenaStars.for_family(family))
		_steps[rank].set_meta("arena_help", "%s %s\n%s" % [ArenaRules.title(ArenaRules.prototype(family,rank)), "★".repeat(rank+1), RemakeText.t("Owned: %d") % count])
	tooltip_text = description(family, owned)

static func description(value: int, army: Array[Dictionary]) -> String:
	var lines: Array[String] = []
	for rank in 3:
		var count := army.filter(func(entry): return int(entry.family) == value and int(entry.rank) == rank).size()
		lines.append("%s %s — %s" % ["★".repeat(rank + 1), ArenaRules.title(ArenaRules.prototype(value, rank)), RemakeText.t("Owned: %d") % count])
	return "\n".join(lines)
