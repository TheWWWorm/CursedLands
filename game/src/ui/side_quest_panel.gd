class_name SideQuestPanel
extends PanelContainer
## Village quest offers from the quest maps (see SideQuests). Accepting sends
## a command to the host, which plays the offer briefing for the whole party.

var hud: GameHUD
var _list: VBoxContainer


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(560, 0)
	var root := VBoxContainer.new()
	add_child(root)
	var title := Label.new()
	title.text = "Village quests"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)
	_list = VBoxContainer.new()
	root.add_child(_list)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): visible = false)
	root.add_child(close)


func open() -> void:
	for c in _list.get_children():
		c.queue_free()
	var s := hud.game.session
	var offers := SideQuests.offers(s)
	var busy := s.state.side_quests.values().any(func(v): return v == "active" or v == "done")
	if offers.is_empty():
		var l := Label.new()
		l.text = "Finish your current task first." if busy else "Nobody here needs help right now."
		_list.add_child(l)
	for q: Dictionary in offers:
		var l := Label.new()
		l.text = "%s  (%s, %d experience)\n%s" % [q.title, s.zone_title(SideQuests.zone_of(s, q)), int(q.exp), q.desc]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.custom_minimum_size.x = 540
		_list.add_child(l)
		var b := Button.new()
		b.text = "Accept"
		b.pressed.connect(func():
			visible = false
			hud.game.issue({"t": "side_quest", "q": q.id}))
		_list.add_child(b)
	visible = true
