class_name ArenaItemTray
extends VBoxContainer
## Persistent inventory, retained by owned UID so authoritative refreshes are safe.

signal item_selected(uid: int)
signal rewards_requested
signal stash_requested
signal cancel_requested
const COLUMNS := 4
const GAP := 4
var run: ArenaRun
var selected_uid := 0
var editable := false
var buttons := {}
var grid: GridContainer
var scroll: ScrollContainer
var stash: Button
var cancel: Button
var rewards: Button
var _empty: Label
var _actions: HBoxContainer
var _heading: Label

func _ready() -> void:
	name = "EquipmentTray"
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_theme_constant_override("separation", GAP)
	var row := HBoxContainer.new()
	add_child(row)
	_heading = Label.new()
	_heading.text = RemakeText.t("Items")
	_heading.add_theme_font_override("font", preload("res://fonts/LiberationSerif-Regular.ttf"))
	_heading.add_theme_font_size_override("font_size", 19)
	_heading.add_theme_color_override("font_color", ArenaCreatureCard.GOLD)
	ArenaCreatureCard.outline(_heading)
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.mouse_filter = Control.MOUSE_FILTER_STOP
	_heading.set_meta("arena_help", RemakeText.t("Click an item, then a creature. You can also drag items onto creatures.") + "\n" + RemakeText.t("No equipment yet. Rewards arrive after round 3, then after every fifth round."))
	row.add_child(_heading)
	rewards = Button.new()
	rewards.text = RemakeText.t("Choose item")
	rewards.add_theme_font_size_override("font_size", 13)
	rewards.pressed.connect(func(): rewards_requested.emit())
	row.add_child(rewards)
	scroll = ScrollContainer.new()
	scroll.name = "ItemTrayScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	grid = GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	scroll.add_child(grid)
	_empty = Label.new()
	_empty.text = RemakeText.t("No items yet")
	_empty.add_theme_font_size_override("font_size", 14)
	_empty.add_theme_color_override("font_color", ArenaCreatureCard.PAPER)
	ArenaCreatureCard.outline(_empty)
	add_child(_empty)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", GAP)
	add_child(_actions)
	stash = Button.new()
	stash.name = "ReturnItemToStash"
	stash.text = RemakeText.t("Return to stash")
	stash.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stash.add_theme_font_size_override("font_size", 13)
	stash.custom_minimum_size.y = 28
	stash.set_meta("arena_help", RemakeText.t("Drop here to return the item to your stash."))
	stash.pressed.connect(func(): stash_requested.emit())
	_actions.add_child(stash)
	cancel = Button.new()
	cancel.text = "×"
	cancel.custom_minimum_size = Vector2(28, 28)
	cancel.accessibility_name = RemakeText.t("Cancel assignment")
	cancel.set_meta("arena_help", RemakeText.t("Cancel assignment") + " · " + RemakeText.t("Escape"))
	cancel.pressed.connect(func(): cancel_requested.emit())
	_actions.add_child(cancel)
	for button in [stash, cancel]:
		for state in ["normal", "hover", "pressed", "focus"]:
			var fill := Color("172322") if state == "normal" else Color("2e3a31")
			var edge := Color("63716c") if state == "normal" else ArenaCreatureCard.GOLD
			button.add_theme_stylebox_override(state, ArenaCreatureCard.style(fill, edge, Vector2(8, 4)))
	synchronize()

func synchronize() -> void:
	if not is_node_ready() or run == null: return
	_heading.set_meta("arena_help", (RemakeText.t("Click an item, then a creature. You can also drag items onto creatures.") if editable else RemakeText.t("Equipment is locked during combat. You can inspect every item.")) + "\n" + (RemakeText.t("No equipment yet. Rewards arrive after round 3, then after every fifth round.") if run.items.is_empty() else RemakeText.t("One item per creature. Change equipment during preparation.")))
	var live := {}
	for index in run.items.size():
		var item: Dictionary = run.items[index]
		var uid := int(item.uid)
		live[uid] = true
		var button: ArenaItemSlot = buttons.get(uid)
		if button == null:
			button = ArenaItemSlot.new()
			button.name = "OwnedItem%d" % uid
			button.set_meta("item_uid", uid)
			grid.add_child(button)
			button.activated.connect(func(): item_selected.emit(uid))
			button.focus_entered.connect(func(): scroll.ensure_control_visible.call_deferred(button))
			buttons[uid] = button
		button.kind = String(item.kind)
		button.selected = selected_uid == uid
		button.equipped = int(item.unit_uid) > 0
		button.attention = editable and not button.equipped
		var holder := run.unit(int(item.unit_uid))
		var carrier := RemakeText.t("In inventory") if holder.is_empty() else RemakeText.t("Equipped by %s") % ArenaRules.title(holder.prototype, int(holder.family), int(holder.rank))
		button.accessibility_name = ArenaItems.title(button.kind) + ", " + carrier
		button.set_meta("arena_item_kind", button.kind)
		button.set_meta("arena_help", ArenaItems.description(button.kind) + "\n\n" + carrier + "\n" + (RemakeText.t("Click an item, then a creature. You can also drag items onto creatures.") if editable else RemakeText.t("Equipment is locked during combat. You can inspect every item.")))
		grid.move_child(button, index)
	for uid in buttons.keys():
		if live.has(uid): continue
		grid.remove_child(buttons[uid])
		buttons[uid].queue_free()
		buttons.erase(uid)
	_empty.visible = run.items.is_empty()
	scroll.visible = not run.items.is_empty()
	rewards.visible = not run.item_offers.is_empty()
	rewards.disabled = not editable
	_actions.visible = selected_uid > 0 and editable
	limit_height(150)

func limit_height(maximum: float) -> void:
	var available := maximum - minimum_height() + ArenaItemSlot.TRAY_SIZE
	var rows := maxi(1, ceili(float(buttons.size()) / COLUMNS))
	var visible_rows := clampi(floori((available + GAP) / (ArenaItemSlot.TRAY_SIZE + GAP)), 1, rows)
	# Scroll whole rows, so the stash control never cuts through item pictures.
	scroll.custom_minimum_size.y = visible_rows * (ArenaItemSlot.TRAY_SIZE + GAP) - GAP

func minimum_height() -> float:
	return _heading.get_parent().get_combined_minimum_size().y + GAP + ArenaItemSlot.TRAY_SIZE + (_actions.get_combined_minimum_size().y + GAP if _actions.visible else 0.0)

func focus_item(uid: int) -> void:
	if buttons.has(uid): buttons[uid].grab_focus()
