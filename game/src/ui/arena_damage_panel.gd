class_name ArenaDamagePanel
extends VBoxContainer
## The player's round roster survives deaths and live-shop purchases. Values
## arrive with authoritative board snapshots, including the local worker.
var rows := {}
var scroll: ScrollContainer
var list: VBoxContainer
var _wait := 0.0

func _ready() -> void:
	add_theme_constant_override("separation",6)
	var heading := Label.new()
	heading.text = RemakeText.t("Damage")
	heading.add_theme_font_override("font",preload("res://fonts/LiberationSerif-Regular.ttf"))
	heading.add_theme_font_size_override("font_size",21)
	heading.add_theme_color_override("font_color",ArenaCreatureCard.GOLD)
	ArenaCreatureCard.outline(heading)
	add_child(heading)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(238,120)
	add_child(scroll)
	list = VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",5); scroll.add_child(list)

func update_damage(battle: ArenaPveMatch, army: Array, maximum_height: float) -> void:
	if not is_instance_valid(list): return
	var entries := army.filter(func(entry):return entry.deployed)
	entries.sort_custom(func(a,b):
		var da := float(battle.friendly_damage.get(int(a.uid),0.0))
		var db := float(battle.friendly_damage.get(int(b.uid),0.0))
		return da > db if not is_equal_approx(da,db) else int(a.uid)<int(b.uid))
	var top := 1.0
	for value in battle.friendly_damage.values(): top = maxf(top,float(value))
	var live := {}
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var uid := int(entry.uid); live[uid]=true
		if not rows.has(uid):
			var row := HBoxContainer.new(); row.add_theme_constant_override("separation",7)
			var portrait := TextureRect.new(); portrait.custom_minimum_size=Vector2(32,32)
			portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
			row.add_child(portrait)
			var text := VBoxContainer.new(); text.size_flags_horizontal=Control.SIZE_EXPAND_FILL; text.size_flags_vertical=Control.SIZE_SHRINK_CENTER; text.add_theme_constant_override("separation",3); row.add_child(text)
			var line := HBoxContainer.new(); text.add_child(line)
			var title := Label.new(); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
			title.add_theme_font_size_override("font_size",15); line.add_child(title)
			var stars := ArenaStars.new(); stars.size_flags_vertical=Control.SIZE_SHRINK_CENTER; line.add_child(stars)
			var value := Label.new(); value.add_theme_font_size_override("font_size",15); line.add_child(value)
			ArenaCreatureCard.outline(title); ArenaCreatureCard.outline(value)
			var bar := ProgressBar.new(); bar.show_percentage=false; bar.custom_minimum_size.y=4; text.add_child(bar)
			bar.add_theme_stylebox_override("background",ArenaCreatureCard.style(Color("25342d"),Color.TRANSPARENT,Vector2.ZERO))
			bar.add_theme_stylebox_override("fill",ArenaCreatureCard.style(Color("a6c981"),Color.TRANSPARENT,Vector2.ZERO))
			list.add_child(row); rows[uid]={"row":row,"portrait":portrait,"title":title,"value":value,"stars":stars,"bar":bar}
		var widgets: Dictionary=rows[uid]
		var amount := float(battle.friendly_damage.get(uid,0.0))
		widgets.title.text = ArenaRules.title(entry.prototype)
		widgets.value.text = str(roundi(amount))
		widgets.row.tooltip_text = "%s %s · %s: %d" % [ArenaRules.title(entry.prototype),"★".repeat(int(entry.rank)+1),RemakeText.t("Damage"),roundi(amount)]
		widgets.portrait.texture = ArenaPortraits.texture(entry.prototype)
		widgets.stars.count = int(entry.rank)+1
		widgets.stars.color = ArenaStars.for_family(int(entry.family))
		widgets.stars.custom_minimum_size=Vector2(widgets.stars.count*14-2,12); widgets.stars.queue_redraw()
		widgets.bar.value = amount/top*100.0
		list.move_child(widgets.row,index)
	for uid in rows.keys():
		if not live.has(uid): list.remove_child(rows[uid].row); rows[uid].row.queue_free(); rows.erase(uid)
	scroll.custom_minimum_size.y = minf(maximum_height,maxf(32,entries.size()*37.0-5.0))
	visible = not entries.is_empty()
