class_name JournalPanel
extends PanelContainer
## Quest journal: active and finished quests with their objectives, built from
## the campaign variables q.<zone>.<quest>[.<n>] and texts.res "quest <id>".
## **Remake addition** (J is free in config/keyboard.ini; the original shows
## quest news only in the message log, L / K). Drawn in the look of the original's
## interface screens: a panel, Times New Roman (CInterface3D font
## 1, title font 2), text with a 1 px shadow.

var hud: GameHUD
var _text: RichTextLabel


func _ready() -> void:
	visible = false
	anchor_left = 0.2
	anchor_right = 0.8
	anchor_top = 0.08
	anchor_bottom = 0.8
	var sb := StyleBoxFlat.new()
	sb.bg_color = Interface800.PANEL
	sb.border_color = Color8(0x6b, 0x5a, 0x3c)
	sb.set_border_width_all(3)
	sb.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var title := Label.new()
	title.text = "Journal"
	title.add_theme_font_override("font", Interface800.font())
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Interface800.TEXT)
	title.add_theme_color_override("font_shadow_color", Interface800.SHADOW)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): visible = false)
	top.add_child(close)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	for f in ["normal_font", "bold_font", "italics_font"]:
		_text.add_theme_font_override(f, Interface800.font())
	_text.add_theme_color_override("default_color", Interface800.TEXT)
	_text.add_theme_color_override("font_shadow_color", Interface800.SHADOW)
	_text.add_theme_constant_override("shadow_offset_x", 1)
	_text.add_theme_constant_override("shadow_offset_y", 1)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_text)


func open() -> void:
	visible = true
	var fs := maxi(10, int(round(get_viewport_rect().size.x * Interface800.FONT_EM[1])))
	for f in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		_text.add_theme_font_size_override(f, fs)
	refresh()


func refresh() -> void:
	if not visible:
		return
	var st := hud.game.session.state
	var active := []
	var done := []
	var objectives := {}   # quest -> {n: state}
	for k: String in st.vars:
		var key := k.get_slice(":", 1)
		if not key.begins_with("q."):
			continue
		var parts := key.split(".")
		if parts.size() == 3:
			(done if float(st.vars[k]) >= 2.0 else active).append(parts[2])
		elif parts.size() == 4:
			objectives.get_or_add(parts[2], {})[int(parts[3])] = float(st.vars[k])
	var out := ""
	for q in active:
		out += _quest(q, objectives.get(q, {}), false)
	if not done.is_empty():
		out += "\n[color=#888888][b]Completed[/b][/color]\n"
		for q in done:
			out += "[color=#888888]%s[/color]\n" % _parse(q).title
	_text.text = out if out else "No quests yet."


func _quest(q: String, objs: Dictionary, _done: bool) -> String:
	var d := _parse(q)
	var s := "[b]%s[/b]\n%s\n" % [d.title, d.text]
	for n in d.subs:
		if objs.has(n):
			var sub: Dictionary = d.subs[n]
			var mark := "[color=#88cc88]✓[/color]" if objs[n] >= 2.0 else "•"
			s += "  %s %s\n" % [mark, sub.title]
			if objs[n] < 2.0 and sub.text:
				s += "     [i]%s[/i]\n" % sub.text
	return s + "\n"


static func _parse(q: String) -> Dictionary:
	var t := SideQuests.quest_doc(q)
	var lines := t.split("\n")
	var out := {"title": lines[0].strip_edges() if lines.size() else q, "text": "", "subs": {}}
	var cur := -1
	for i in range(1, lines.size()):
		var l := lines[i].strip_edges()
		if l.begins_with("#subobj"):
			cur = l.substr(7).strip_edges().to_int()
			out.subs[cur] = {"title": "", "text": ""}
		elif l:
			if cur < 0:
				out.text += l + " "
			elif out.subs[cur].title == "":
				out.subs[cur].title = l
			else:
				out.subs[cur].text += l + " "
	return out
