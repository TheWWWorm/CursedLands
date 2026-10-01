class_name InventoryPanel
extends PanelContainer
## Party bag (shared in co-op), the selected hero's equipment and belt, and
## the shop when the party is in a settlement. Every change is a command to
## the host (see Session._item_command / _trade).

var hud: GameHUD
var shop_mode := false
var _money: Label
var _hero_box: VBoxContainer
var _doll: Paperdoll
var _bag: ItemList
var _right: ItemList
var _right_title: Label
var _info: Label
var _buttons: HFlowContainer
var _bag_ids: Array = []
var _right_ids: Array = []
var _root: VBoxContainer
var _cols: HBoxContainer
var _hero_scroll: ScrollContainer
var _camp: CampView
## The hero picked with the camp hero widget's arrows (uid; -1 = selection).
var _hero_uid := -1


func _ready() -> void:
	visible = false
	anchor_left = 0.12
	anchor_right = 0.88
	anchor_top = 0.08
	anchor_bottom = 0.8
	var root := VBoxContainer.new()
	_root = root
	add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	var title := Label.new()
	title.text = "Inventory"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_money = Label.new()
	top.add_child(_money)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): visible = false)
	top.add_child(close)

	var cols := HBoxContainer.new()
	_cols = cols
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	var left := VBoxContainer.new()
	cols.add_child(left)
	_doll = Paperdoll.new()
	left.add_child(_doll)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.x = 290
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_hero_scroll = scroll
	left.add_child(scroll)
	_hero_box = VBoxContainer.new()
	_hero_box.custom_minimum_size.x = 280
	scroll.add_child(_hero_box)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(mid)
	var bl := Label.new()
	bl.text = "Party bag"
	mid.add_child(bl)
	_bag = ItemList.new()
	_bag.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bag.item_selected.connect(func(i): _select(_bag_ids[i], "bag"))
	mid.add_child(_bag)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	_right_title = Label.new()
	right.add_child(_right_title)
	_right = ItemList.new()
	_right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right.item_selected.connect(func(i): _select(_right_ids[i], "shop" if shop_mode else "worn"))
	right.add_child(_right)

	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info.custom_minimum_size.y = 60
	root.add_child(_info)
	_buttons = HFlowContainer.new()
	root.add_child(_buttons)
	# Camp / settlement dressing screen in the original's look (CampView).
	_camp = CampView.new()
	_camp.hud = hud
	_camp.visible = false
	_camp.picked.connect(func(id, where): _select(id if where != "belt" else "belt:" + id,
		"worn" if where in ["worn", "belt"] else where))
	_camp.deal.connect(_on_deal)
	_camp.construct.connect(_issue)
	_camp.repair.connect(func(items): for it in items: _issue({"t": "repair", "item": it}))
	_camp.mode_changed.connect(func(m): shop_mode = not m in ["weapons", "spells"]; _info.text = ""; _clear_buttons())
	add_child(_camp)
	_camp.exit_pressed.connect(func(): visible = false)   # Exit (tip 20107)
	_camp.hero_step.connect(_step_hero)


## `constr`: the trader picked from the topic list ("constr<N>", Shops); 0 opens
## the dressing screen alone (the global map's camp button, constr.current 0).
func open(shop: bool, constr := 0) -> void:
	_camp.shop_id = constr if shop else 0
	Items.coef = Shops.coef(_camp.shop_id)
	shop_mode = _camp.shop_id != 0
	_set_camp(true)
	_camp.set_mode(_camp.first_mode())
	visible = true
	refresh()
	if _camp.visible:
		_camp.screen_tutorial()   # (0)


## Esc leaves the camp / shop screen as its Exit button does (tip 20107);
## without this the key reached the Esc signpost, which opened underneath the
## full-screen camp. The camp's key handler: Esc → (7)
## (mode button 7, Exit); Enter in a network game opens the chat line
## (ui/chat_line.gd); Backspace in a network game clears the chat
## list (not ported, see ChatLine); other keys.
func _unhandled_key_input(e: InputEvent) -> void:
	if not (visible and e is InputEventKey and e.pressed and not e.echo):
		return
	if _camp.visible and _camp.tutorial_visible():
		return   # the tutorial window has the keys
	if e.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()
	elif e.keycode in [KEY_ENTER, KEY_KP_ENTER] and hud.game.session.online:
		hud.chat_line.open()
		get_viewport().set_input_as_handled()
	elif _camp.visible and EIKeymap.action(e.keycode) == "tutorial_script":
		_camp.screen_tutorial(true)   # (1)
		get_viewport().set_input_as_handled()


## Shop commands name the trader of this camp screen (Session.shop_id).
func _issue(cmd: Dictionary) -> void:
	if cmd.get("t", "") in ["buy", "sell", "repair", "construct", "deconstruct"]:
		cmd["shop"] = _camp.shop_id
	_sound(String(cmd.get("t", "")))
	hud.game.issue(cmd)


## Dressing / hero screen sounds (2D): an item put on the hero
## or its belt "buttons\camp\put_on.wav", taken
## off "put_off.wav"; a skill raised or an ability learnt
## "perk.wav".
func _sound(t: String) -> void:
	var wav := ""
	match t:
		"equip", "give_quick": wav = "buttons\\camp\\put_on.wav"
		"unequip": wav = "buttons\\camp\\put_off.wav"
		"train", "perk": wav = "buttons\\camp\\perk.wav"
	if wav and GameSound.instance:
		GameSound.instance.ui(wav)


## Camp screen: full window in the original's look (CampView draws the hero,
## item info and deal widgets); the remake's action buttons sit at the bottom
## of its right info widget. Off: the old list layout.
func _set_camp(on: bool) -> void:
	if on:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		offset_left = 0
		offset_top = 0
		offset_right = 0
		offset_bottom = 0
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		anchor_left = 0.12
		anchor_right = 0.88
		anchor_top = 0.08
		anchor_bottom = 0.8
		remove_theme_stylebox_override("panel")
	_root.visible = not on
	_camp.visible = on
	# The camp draws its own item info and hero widgets; the remake's action
	# buttons go to the bottom of its right info widget.
	var dest: Node = _camp.right_panel if on else _root
	if _buttons.get_parent() != dest:
		_buttons.get_parent().remove_child(_buttons)
		dest.add_child(_buttons)


func _hero() -> GameUnit:
	var g := hud.game
	if _hero_uid >= 0:
		for u: GameUnit in g.my_units():
			if u.uid == _hero_uid and u.has_meta("hero"):
				return u
	if not g.selected.is_empty() and g.selected[0].has_meta("hero"):
		return g.selected[0]
	var mine := g.my_units()
	return mine[0] if not mine.is_empty() else null


func refresh() -> void:
	if not visible:
		return
	var st := hud.game.session.state
	_money.text = "Gold: %d   " % st.money
	for c in _hero_box.get_children():
		c.queue_free()
	var u := _hero()
	_camp.refresh(u)
	_doll.visible = u != null and not _camp.visible
	if u:
		_doll.show_unit(u)
	if u and u.has_meta("hero"):
		var h: Dictionary = u.get_meta("hero")
		var l := Label.new()
		l.text = "%s\nHealth %d/%d   Stamina %d/%d\nStr %d  Dex %d  Int %d\nAttack %d  Defense %d\nDamage %.0f-%.0f   Armor %.1f\nLoad %d/%d\nExperience %d (free %d)" % [
			u.display_name, u.hp, u.max_hp, u.mana, u.max_mana, h.get("str", 0), h.get("dex", 0), h.get("int", 0),
			u.stats.get("to_hit", 0), u.stats.get("parry", 0),
			u.stats.get("dmg_min", 0), u.stats.get("dmg_max", 0), u.stats.get("absorption", 0),
			u.stats.get("load", 0), u.stats.get("max_load", 0),
			h.get("exp_total", 0), h.get("exp", 0)]
		_hero_box.add_child(l)
		var spells: Array = h.get("spells", [])
		if not spells.is_empty():
			var sl := Label.new()
			sl.text = "Spells: " + ", ".join(spells.map(func(x): return Spells.title(x)))
			sl.autowrap_mode = TextServer.AUTOWRAP_WORD
			sl.custom_minimum_size.x = 270
			_hero_box.add_child(sl)
		var town := hud.game.session.shop_available()   # management only in towns and camps
		# The six original skills (0..100); raised with experience in towns and camps.
		for skill: String in Skills.LIST:
			var cost := Skills.cost(h, skill)
			var b := Button.new()
			b.text = "%s %d" % [Skills.title(skill), Skills.level(h, skill)] + ("   + (%d exp)" % cost if town and cost > 0 else "")
			b.disabled = not town or cost <= 0 or float(h.get("exp", 0.0)) < cost or u.controller != hud.game.session.my_index
			b.pressed.connect(_issue.bind({"t": "train", "unit": u.uid, "stat": skill}))
			_hero_box.add_child(b)
		var known: Array = h.get("perks", [])
		if not known.is_empty():
			var pl := Label.new()
			pl.text = "Abilities: " + ", ".join(known.map(func(x): return Perks.title(x)))
			pl.autowrap_mode = TextServer.AUTOWRAP_WORD
			pl.custom_minimum_size.x = 270
			_hero_box.add_child(pl)
		var perk_btn := MenuButton.new()
		perk_btn.visible = town
		perk_btn.text = "Learn an ability..."
		perk_btn.flat = false
		var pm := perk_btn.get_popup()
		var avail := Perks.available(h)
		for i in avail.size():
			var c := Perks.cost(avail[i], h)
			pm.add_item("%s  (%d exp)" % [Perks.title(avail[i]), c], i)
			pm.set_item_disabled(i, float(h.get("exp", 0.0)) < c)
		pm.id_pressed.connect(func(i): _issue({"t": "perk", "unit": u.uid, "perk": avail[i]}))
		perk_btn.disabled = u.controller != hud.game.session.my_index or avail.is_empty()
		_hero_box.add_child(perk_btn)
	_bag.clear()
	_bag_ids.clear()
	var counts := {}
	for it: String in st.items:
		counts[it] = int(counts.get(it, 0)) + 1
	for it: String in counts:
		_bag.add_item("%s%s" % [Items.title(it), " x%d" % counts[it] if counts[it] > 1 else ""])
		_bag_ids.append(it)
	_right.clear()
	_right_ids.clear()
	if shop_mode:
		_right_title.text = "Shop"
		for it: String in hud.game.session.shop_stock({"shop": _camp.shop_id}):
			_right.add_item("%s  -  %d gold" % [Items.title(it), Items.buy_price(it)])
			_right_ids.append(it)
	else:
		_right_title.text = "Equipped / belt"
		if u and u.has_meta("hero"):
			var h: Dictionary = u.get_meta("hero")
			for it in h.get("weapons", []) + h.get("armors", []):
				_right.add_item("[%s] %s" % [Items.slot(it), Items.title(it)])
				_right_ids.append(it)
			for it in h.get("quick", []):
				_right.add_item("[belt] %s" % Items.title(it))
				_right_ids.append("belt:" + it)
	_info.text = ""
	for c in _buttons.get_children():
		c.queue_free()


## The camp hero widget's arrows: the previous / next hero of the party.
func _step_hero(dir: int) -> void:
	var heroes := hud.game.my_units().filter(func(u): return u.has_meta("hero"))
	if heroes.is_empty():
		return
	var cur := heroes.find(_hero())
	_hero_uid = heroes[posmod(cur + dir, heroes.size())].uid
	_clear_buttons()
	refresh()


func _clear_buttons() -> void:
	for c in _buttons.get_children():
		c.queue_free()


## A trade screen's Yes: sell first (the gold pays for the purchases), then buy.
func _on_deal(buy: Array, sell: Array) -> void:
	var u := _hero()
	for it in sell:
		_issue({"t": "sell", "item": it})
	for it in buy:
		_issue({"t": "buy", "item": it, "unit": u.uid if u else -1})


func _select(id: String, where: String) -> void:
	_clear_buttons()
	var item := id.trim_prefix("belt:")
	_info.text = _camp.item_info_text(item)   # the camp info widget's text
	if where == "info":
		return
	var u := _hero()
	var uid := u.uid if u else -1
	match where:
		"bag":
			var town := hud.game.session.shop_available()
			if Items.slot(item) != "" and town:
				_button("Equip", {"t": "equip", "unit": uid, "item": item})
			if Items.kind(item) == "quick":
				_button("Put on belt", {"t": "give_quick", "unit": uid, "item": item})
			if item.begins_with("spell:") and town:
				_button("Learn", {"t": "learn", "unit": uid, "item": item})
			if Items.kind(item) == "rune" and u and u.has_meta("hero") and town:
				var hh: Dictionary = u.get_meta("hero")
				for sp in hh.get("spells", []):
					if Spells.can_add(sp, item.substr(5)):
						_button("Into %s" % Spells.title(sp), {"t": "enchant", "unit": uid, "item": item, "spell": sp})
				# Item runes: put a known spell on a worn or carried weapon / armour.
				var shown := {}
				for tgt: String in hh.get("weapons", []) + hh.get("armors", []) + hud.game.session.state.items:
					if shown.has(tgt) or item != "rune:" + Items.enchant_rune(tgt):
						continue
					shown[tgt] = true
					for sp in hh.get("spells", []):
						if Items.can_enchant(tgt, sp):
							_button("%s on %s" % [Spells.title(sp).get_slice(" (", 0), Items.title(tgt)],
								{"t": "enchant_item", "unit": uid, "item": item, "target": tgt, "spell": sp})
			if shop_mode and Items.kind(item) != "quest":
				_button("Sell (%d)" % Items.sell_price(item), {"t": "sell", "item": item})
			# Repair and the constructor belong to a trader's item group (Shops).
			var smith := Shops.sells_items(_camp.shop_id)
			if smith and Items.wear(item) > 0.0:
				_button("Repair (%d)" % Items.repair_price(item), {"t": "repair", "item": item})
			if smith and Items.can_deconstruct(item):
				_button("Deconstruct (%d)" % Items.deconstruct_price(item), {"t": "deconstruct", "item": item})
			if smith and Items.kind(item) == "blueprint":
				_construct_buttons(item)
		"worn":
			if id.begins_with("belt:"):
				_button("Use", {"t": "use", "unit": uid, "item": item})
			elif hud.game.session.shop_available():
				_button("Unequip", {"t": "unequip", "unit": uid, "item": item})
				if Items.wear(item) > 0.0 and Shops.sells_items(_camp.shop_id):
					_button("Repair (%d)" % Items.repair_price(item), {"t": "repair", "unit": uid, "item": item})
		"shop":
			_button("Buy (%d)" % Items.buy_price(item), {"t": "buy", "item": item, "unit": uid})
			if Items.kind(item) == "blueprint":
				_construct_buttons(item)


## One button per material the blueprint takes; missing pieces are bought from
## the shop in the same deal (Session._construct).
func _construct_buttons(bp: String) -> void:
	var s: Session = hud.game.session
	var n := Items.components(bp)
	for m: Dictionary in Items.materials_for(bp):
		var unit := Items.material_unit(String(m.name).to_lower())
		var have := s.state.items.count(unit)
		if have < n and s.shop_count(unit, {"shop": _camp.shop_id}) < n - have:
			continue
		var cost := Items.construct_price(bp, String(m.name).to_lower()) + maxi(0, n - have) * Items.buy_price(unit)
		if not bp in s.state.items:
			cost += Items.buy_price(bp)
		_button("Build with %s (%d)" % [Items.title(unit), cost], {"t": "construct", "bp": bp, "mat": String(m.name).to_lower()})


func _button(text: String, cmd: Dictionary) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func(): _issue(cmd))
	_buttons.add_child(b)
