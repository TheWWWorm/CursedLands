class_name GameHUD
extends CanvasLayer
## In-game interface: party panel, message log, hover info, menus, dialogs.

var game: Game
## Run / walk and the posture are per unit (the original unit
## GameUnit.gait_run); these read the selection's (true / STANCE_* of the
## first selected unit).
var run_mode: bool:
	get:
		var u := _first_selected()
		return u != null and u.gait_run
var stance: int:
	get:
		var u := _first_selected()
		return u.stance if u else 0
var _log: RichTextLabel
var text_window: MessageLog
var minimap: Minimap
var _field: Control   # the field screen's CInterface3D widgets
var _field_on := true
var _party: VBoxContainer
var _menu: EscSignpost
var _options: OptionsPanel
var _save_load: LoadPanel
var _esc_bg: Interface800.Backdrop
var _esc_open := false
var _esc_frame: Image
var _quit_box: MessageBox
var _game_over_box: MessageBox
var _game_over_load := false   # the Load screen came from the game-over box
var _death_notice: GameOverNotice   # remake option "sp_death_notice"
var _pause_before: Variant = null   # interface manager: the pause state to restore
var _dialog: DialogPanel
var _travel: Control
var _inventory: InventoryPanel
var _journal: JournalPanel
var _side_quests: SideQuestPanel
var _tutorial: TutorialPanel
var _movie: MoviePlayer
var _target_label: Label
var _notify: NotifyLine
var _spell_owner: GameUnit
var _faces: PartyFaces
var _world: GameWorld
var _move_dial: HudDial
var _clock_dial: HudDial
var _weapons: WeaponBar
var _slots: SpellSlots
var _actions: ActionStrip
var _belt: BeltStrip
var unit_panel: UnitPanel
var chat_line: ChatLine
var touch_actions: TouchActions
var _safe_root: Control


func _ready() -> void:
	_safe_root = Control.new()
	_safe_root.name = "SafeArea"
	_safe_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_safe_root)
	_layout_safe_area()
	# CInterface3D (the original, slot 25 of the field screen's
	# ): the widgets below exist only on the field screen. The village
	# screen (case 3, build) builds
	# none of them, so in "brief" zones the whole group is hidden.
	_field = Control.new()
	_field.name = "Field"
	_field.set_anchors_preset(Control.PRESET_FULL_RECT)
	_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_ui(_field)
	# Top centre as the original's message log widget (ui/message_log.gd).
	text_window = MessageLog.new()
	_field.add_child(text_window)
	_log = text_window.messages

	# The party list sits below the unit panel (0..225 of the 800×600 layout).
	var top_left := VBoxContainer.new()
	top_left.anchor_top = 235.0 / 600.0
	top_left.offset_left = 6
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_ui(top_left)
	var panel := PanelContainer.new()
	panel.visible = false   # nothing left in it (see _rebuild_party)
	top_left.add_child(panel)
	_party = VBoxContainer.new()
	panel.add_child(_party)
	unit_panel = UnitPanel.new()
	unit_panel.game = game
	_field.add_child(unit_panel)

	# Party faces bottom centre in the original layout (ui/party_faces.gd).
	_faces = PartyFaces.new()
	_faces.game = game
	_field.add_child(_faces)


	_move_dial = _dial("move", Vector2(0, 1))
	_move_dial.sector_pressed.connect(func(i: int): set_move_mode(["crawl", "sneak", "walk", "run"][i]))
	_move_dial.inner_pressed.connect(toggle_aggression)
	_weapons = WeaponBar.new()
	_weapons.game = game
	_weapons.anchor_top = 1.0
	_weapons.anchor_bottom = 1.0
	_field.add_child(_weapons)
	_actions = ActionStrip.new()
	_actions.game = game
	_actions.anchor_top = 1.0
	_actions.anchor_bottom = 1.0
	_field.add_child(_actions)
	_belt = BeltStrip.new()
	_belt.game = game
	_belt.anchor_left = 1.0
	_belt.anchor_right = 1.0
	_belt.anchor_top = 1.0
	_belt.anchor_bottom = 1.0
	_field.add_child(_belt)
	_slots = SpellSlots.new()
	_slots.game = game
	_slots.anchor_left = 1.0
	_slots.anchor_right = 1.0
	_slots.anchor_top = 1.0
	_slots.anchor_bottom = 1.0
	_field.add_child(_slots)
	_clock_dial = _dial("clock", Vector2(1, 1))
	_clock_dial.sector_pressed.connect(func(i: int): game.set_speed(i))
	_clock_dial.inner_pressed.connect(func(): game.open_quests())   # tip 10401: the quests screen

	minimap = Minimap.new()
	minimap.game = game
	_field.add_child(minimap)

	# Global map (ui/travel_map.gd), full screen under the Esc menu (its Esc
	# key), the options and the camp screen (its camp button).
	_travel = Control.new()
	_travel.visible = false
	_travel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_travel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_ui(_travel)

	# The Esc menu opens as a modal screen over the game ((menu
	# 1, 1) from the Esc key, e.g.): the frame is captured once
	# greyed and shown frozen under it and the screens it opens (
	# state 1); its 256×192 copy is the Save screen's shot.
	_esc_bg = Interface800.dim_layer()
	_esc_bg.show_behind_parent = false
	_esc_bg.visible = false
	_add_ui(_esc_bg)
	_menu = EscSignpost.new()
	_menu.visible = false
	_menu.pressed.connect(_on_signpost)
	_add_ui(_menu)
	_options = OptionsPanel.new()
	_add_ui(_options)
	_options.closed.connect(_close_menu)
	_save_load = LoadPanel.new()
	_add_ui(_save_load)
	_save_load.closed.connect(func():
		if _game_over_load:   # → the main menu; a load goes
			_game_over_load = false
			if not _save_load.loading:
				_on_esc_board("exit")
				return
		_close_menu())
	_save_load.save_requested.connect(func(slot: String, save_name: String, frame: Image):
		game.session.save_game(slot, save_name, frame))
	_save_load.load_requested.connect(func(slot: String):
		if not game.session.load_game(slot):
			log_msg(RemakeText.t("Load failed.")))

	_target_label = Label.new()
	_target_label.anchor_left = 0.5
	_target_label.anchor_right = 0.5
	_target_label.offset_left = -200
	_target_label.offset_right = 200
	_target_label.offset_top = 12
	_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_label.add_theme_constant_override("outline_size", 4)
	_target_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_add_ui(_target_label)
	_notify = NotifyLine.new()
	_add_ui(_notify)

	_inventory = InventoryPanel.new()
	_inventory.hud = self
	_add_ui(_inventory)
	_journal = JournalPanel.new()
	_journal.hud = self
	_add_ui(_journal)
	_side_quests = SideQuestPanel.new()
	_side_quests.hud = self
	_add_ui(_side_quests)
	_tutorial = TutorialPanel.new()
	_add_ui(_tutorial)
	_movie = MoviePlayer.new()
	_movie.hud = self
	_add_ui(_movie)

	# The village screen's name under the cursor (VillageName).
	var vname := VillageName.new()
	vname.game = game
	_add_ui(vname)
	_safe_root.move_child(vname, _movie.get_index())
	# Remake option "revive": "Help … up" under the cursor, the work's progress.
	var rv := ReviveOverlay.new()
	rv.game = game
	_add_ui(rv)
	_safe_root.move_child(rv, _movie.get_index())
	_dialog = DialogPanel.new()
	_dialog.hud = self
	_add_ui(_dialog)
	# Co-op: player list and chat input (remake; NetStatus).
	var players := PlayerList.new()
	players.game = game
	_add_ui(players)
	chat_line = ChatLine.new()
	chat_line.game = game
	_add_ui(chat_line)
	_chat = ChatOverlay.new()
	_add_ui(_chat)
	touch_actions = TouchActions.new()
	touch_actions.game = game
	_add_ui(touch_actions)


func on_world(w: GameWorld) -> void:
	if w != _world:
		_world = w
		w.combat_event.connect(_on_combat)
		w.unit_died.connect(_on_died)
		if not game.session.message.is_connected(log_msg):
			game.session.message.connect(log_msg)
		if not game.session.net.chat.is_connected(log_chat):
			game.session.net.chat.connect(log_chat)
		# No zone-entry line: the original adds nothing to the message log on a zone
		# load (texts.res has no such string; only builds the
		# "Collected items" listing below).
		#  runs once as the interface is built (zone load).
		text_window.build_listing(game.session.state.money, game.session.state.items)
		# Remake (co-op): the zone changed under an open conversation or
		# trader screen (another player travelled); the old zone's briefing is
		# gone with its world, so both close (a replayed one opens again).
		_dialog.visible = false
		if _inventory.visible and _inventory.shop_mode:
			_inventory.visible = false
	_rebuild_party()


func _on_died(_u: GameUnit, _k: GameUnit) -> void:
	pass   # no death line in the original's message log (see _on_combat)


func _rebuild_party() -> void:
	for c in _party.get_children():
		c.queue_free()
	_faces.rebuild()
	# The original HUD has no text buttons: movement mode, stance and speed are
	# on the corner dials, the side quests on the clock dial's inner disc,
	# inventory / journal on their keys (B, J). Traders open only from their
	# "constr<N>" topic.


## Corner dial sized from the original's 800×600 layout (80 px of 600).
func _dial(kind: String, corner: Vector2) -> HudDial:
	var d := HudDial.new()
	d.kind = kind
	d.anchor_left = corner.x
	d.anchor_right = corner.x
	d.anchor_top = corner.y
	d.anchor_bottom = corner.y
	_field.add_child(d)
	return d


func _layout_dials() -> void:
	var s := roundf(ui_size().y * 80.0 / 600.0)
	if TouchInput.enabled:
		s = maxf(s, TouchInput.target_pixels() * 1.25 / minf(transform.get_scale().x, transform.get_scale().y))
	_move_dial.offset_left = 0
	_move_dial.offset_right = s
	_move_dial.offset_top = -s
	_move_dial.offset_bottom = 0
	_clock_dial.offset_left = -s
	_clock_dial.offset_right = 0
	_clock_dial.offset_top = -s
	_clock_dial.offset_bottom = 0
	# Exe layout in units of the 800×600 screen: s = 80 of them.
	_weapons.offset_left = s
	_weapons.offset_right = s * 3.0
	_weapons.offset_top = -s
	_weapons.offset_bottom = 0
	_actions.offset_left = 0
	_actions.offset_right = s * 40.0 / 80.0
	_actions.offset_top = -s * 350.0 / 80.0
	_actions.offset_bottom = -s * 90.0 / 80.0
	# Spells in the right-edge column (760,190)-(800,510), the
	# belt's quick items in 520..720 × 500..600.
	_slots.offset_left = -s * 40.0 / 80.0
	_slots.offset_right = 0
	_slots.offset_top = -s * 410.0 / 80.0
	_slots.offset_bottom = -s * 90.0 / 80.0
	_belt.offset_left = -s * 280.0 / 80.0
	_belt.offset_right = -s
	_belt.offset_top = -s * 100.0 / 80.0
	_belt.offset_bottom = 0
	if TouchInput.enabled:
		# Enlarge the original item cells; keep their artwork, arrangement and
		# corner anchors. A short phone scrolls the existing spell column.
		var cell := Vector2.ONE * TouchInput.target_pixels() / transform.get_scale()
		_belt.offset_left = -s - maxf(s * 2.5, cell.x * 4)
		_belt.offset_top = -maxf(s * 1.25, cell.y * 2)
		_slots.offset_left = -maxf(s * 0.5, cell.x)
		_slots.offset_top = _slots.offset_bottom - minf(-_slots.offset_left * 8, ui_size().y * 0.55)
	# The targeting hint (remake-only) under the text window (0..100).
	_target_label.offset_top = s * 104.0 / 80.0
	var sel := _selected_gait()
	var clock := 0 if game.get_tree().paused else 1 + game.speed
	var aggr := _selected_aggression()
	if sel != _move_dial.selected or clock != _clock_dial.selected or aggr != _move_dial.aggression:
		_move_dial.selected = sel
		_move_dial.aggression = aggr
		_clock_dial.selected = clock
		_move_dial.queue_redraw()
		_clock_dial.queue_redraw()
	var hour: float = game.session.state.world_time if game.session and game.session.state else 12.0
	# Sun (atlas left) mid-quadrant at noon, moon at midnight.
	var ang := PI * 0.25 + (hour - 12.0) / 24.0 * TAU
	if absf(ang - _clock_dial.ring_angle) > 0.002:
		_clock_dial.ring_angle = ang
		_clock_dial.queue_redraw()


func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(Portrait.SIZE.x, 5)
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	b.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	b.add_theme_stylebox_override("background", bg)
	return b


## The save / load notice (NotifyLine).
func notify(key: String) -> void:
	if _notify:
		_notify.notify(key)


func set_targeting(spell_title: String) -> void:
	_target_label.text = "" if spell_title.is_empty() else RemakeText.t("Cast %s: click a target (right click cancels)") % spell_title


## The unit under the mouse is shown by the unit panel (shows
## the hovered unit, else the selected one); the original draws no name label
## the cursor, so the remake's earlier one is gone.
func _process(_dt: float) -> void:
	_layout_safe_area()
	_layout_dials()
	# Village ("brief" zone) = the village screen without CInterface3D.
	var field: bool = game == null or game.session == null or not game.session.shop_available()
	if field != _field_on or (not field and _field.visible):
		_field_on = field
		_field.visible = field


## Combat writes nothing to the message log: texts.res has no hit / death /
## backstab lines (the original's combat_* strings are quest, pick-up and
## "Broken:" notes); hits show as FlyingHP numbers ("hitnum" events).
func _on_combat(_kind: String, _a: GameUnit, _b: GameUnit, _amount: float) -> void:
	pass


## A co-op chat line (NetStatus): the name in the player's colour, then ": text".
## A chat message (NetStatus "chat"): the original's chat object's overlay lines
## (ChatOverlay), not the text window.
func log_chat(idx: int, player_name: String, text: String) -> void:
	_chat.add(idx, player_name, text)


var _chat: ChatOverlay


## Backspace in a network game: the chat list is
## emptied.
func clear_chat() -> void:
	_chat.clear()


func log_msg(text: String, color := Color.WHITE) -> void:
	if _dialog and _dialog.visible:
		_dialog.note(text)
	_log.push_color(color)
	_log.add_text(text + "\n")
	_log.pop()


## A q.* var changed (the original of the top
## screen; only the field screen has one, — under the village
## a conversation or any other screen nothing is shown or heard). One line
## per var in the text window: a quest (3 parts) «string combat_get_quest» /
## combat_complete_quest (2) / combat_failed_quest (3) and the first line of
## «quest <id>», in colour ee e3 31; an objective (4 parts) combat_get_subobj /
## combat_complete_subobj / combat_failed_subobj and the line after its
## "#subobj <n>", in ff b3 31 — skipped in single player while the quest's
## own var is 0. The sound priority = max(its value
## 3 for a completed quest, else the var's value, 1 for a failed one) picks
## one sound per frame in the field update: 1 buttons\quest.wav
## 2 buttons\subcomplete.wav, 3 buttons\complete.wav. **Not ported**: the
## quest-scroll disc's 1 s pulse until the objectives are opened (dial
## ) and the messenger bird of a completed quest.
## **Approx.**: "another screen on top" = the remake's village mode or an open
## dialog / inventory / journal / side quest / travel / Esc panel.
var _quest_sound := 0


func _quest_note(key: String, value: float) -> void:
	var parts := key.split(".")
	if parts.size() < 3 or parts.size() > 4:
		return
	_quest_flash(key)
	if parts.size() == 3 and value == 2.0:
		_send_bird()
	var v := int(value)
	var sub := parts.size() == 4
	if sub and not game.session.online \
			and game.session.state.get_var(0, "q.%s.%s" % [parts[1], parts[2]]) == 0.0:
		return
	if _clock_dial:
		_clock_dial.pulse = true   # dial = 1
	if not _field_on or _esc_open or (_dialog and _dialog.visible) or _inventory.visible \
			or _journal.visible or _side_quests.visible or _travel.visible:
		return
	var what := "subobj" if sub else "quest"
	var kind := "complete" if v == 2 else "failed" if v == 3 else "get"
	var doc := JournalPanel._parse(parts[2])
	var title: String = doc.title
	if sub:
		var n := parts[3].to_int()
		title = String(doc.subs[n].title) if doc.subs.has(n) else ""
	var label := GameData.text("string combat_%s_%s" % [kind, what]).strip_edges()
	log_msg("%s %s" % [label, title], Color8(0xff, 0xb3, 0x31) if sub else Color8(0xee, 0xe3, 0x31))
	var prio := 3 if (not sub and v == 2) else (1 if v == 3 else v)
	if prio > _quest_sound:
		if _quest_sound == 0:
			_play_quest_sound.call_deferred()
		_quest_sound = prio


## every client object whose.mob OBJ_QUEST_INFO equals
## (stricmp) the var name after its second dot gets
## . For units that is: particle 0x2043 (sparks) on the
## unit (carrier, bone = 7), size = the unit's radius, =
## 10, whatever the value, and the figure's 4-tick white flash ((4)
## OrderMarks.flash). Approx.: the other classes' (the
##  model) is not ported.
func _quest_flash(key: String) -> void:
	var w: GameWorld = game.session.world if game and game.session else null
	var i1 := key.find(".")
	var i2 := key.find(".", i1 + 1) if i1 >= 0 else -1
	if w == null or i2 < 0:
		return
	var name := key.substr(i2 + 1).to_lower()
	var fx := ParticleFx.of(w)
	for u: GameUnit in w.units.values():
		if is_instance_valid(u) and String(u.info.get("quest_info", "")).to_lower() == name:
			fx.spawn(0x2043, Vector3.ZERO, fx.carrier_size(u).y, u, {"k118": 10.0, "bone": 7})
			if game.marks:
				game.marks.flash(u, 4)


## a whole quest at 2 sends the messenger bird to the local
## player's hero (see QuestBird).
func _send_bird() -> void:
	var w: GameWorld = game.session.world if game.session else null
	if w == null:
		return
	for u: GameUnit in w.units.values():
		if u.controller == game.session.my_index and u.has_meta("hero") \
				and not u.get_meta("hero").has("merc") and not u.dead:
			QuestBird.visit(w, u)
			return


func _play_quest_sound() -> void:
	var wav: String = ["", "buttons\\quest.wav", "buttons\\subcomplete.wav", "buttons\\complete.wav"][clampi(_quest_sound, 0, 3)]
	_quest_sound = 0
	if wav and GameSound.instance:
		GameSound.instance.ui(wav)


func on_event(e: Dictionary) -> void:
	match String(e.get("t", "")):
		"dialog": _dialog.show_briefing(e)
		"topics":
			if int(e.get("player", -1)) == game.session.my_index:
				_dialog.show_topics(e)
		"shop":   # a "constr*" topic (Briefings.topic)
			if int(e.get("player", -1)) == game.session.my_index and game.session.shop_available():
				_inventory.open(true, int(e.get("constr", 0)))
		"dialog_close":
			if _dialog.visible and _dialog._id == String(e.id):
				_dialog.visible = false
		"journal":
			_journal.refresh()
			_quest_note(String(e.get("key", "")), float(e.get("value", 0.0)))
		"inventory":
			_inventory.refresh()
			_rebuild_party()
		"travel": _show_travel(e.options, String(e.get("from", "")), e.get("start", []))
		"travel_close": _close_travel()
		"tutorial": _tutorial.show_tutorial(String(e.id))
		"movie":
			_movie.pause_game = not game.session.online
			_movie.play(String(e.get("name", "")))
		"party": _rebuild_party()
		"game_over": _show_game_over()
		"death_notice":   # remake option "revive": the hint that a companion can help
			show_death_notice(RemakeText.t(ReviveOverlay.NOTICE_HINT) if e.get("revive", false) else "")
		"ending": _show_ending()
		"end_of_game": _show_end_of_game()
		"leave_box":
			if int(e.get("to", 0)) == game.session.my_index:
				_show_leave_box(int(e.get("exit", -1)))
		"got":
			if int(e.get("to", -1)) in [-1, game.session.my_index]:
				_got_items(e)
		"constr_result":   # Session._spell_constr's answer to this player's camp screen
			if int(e.get("to", -1)) == game.session.my_index:
				_inventory._camp.constr_result(e)


## Client message 6 (handler: the items join the player's bag
## ), CInterface3D slot: one
## message-window line per item,: «combat_picked_up» ("You picked
## up:"), or «combat_crippled» ("Broken:") when the server's flag is set (only
## the worn-out equipment moved to the bag), + " " + the item
##  + "\n"; then: for a money gain > 0
## «combat_picked_up» + " " + «format_money» ("Money (%d)") + "\n".
## The item text is Items.log_text (: «format_item1» with the
## type line and the quoted name).
func _got_items(e: Dictionary) -> void:
	#  calls the top screen: only CInterface3D (the field) has the
	# window; a conversation shows its rewards itself (DialogPanel).
	if not _field_on or _esc_open or (_dialog and _dialog.visible) or _inventory.visible \
			or _journal.visible or _side_quests.visible or _travel.visible:
		return
	var label := GameData.text("string " + ("combat_crippled" if e.get("broken", false) else "combat_picked_up")).strip_edges()
	for it in e.get("items", []):
		log_msg("%s %s" % [label, Items.log_text(String(it))])
	var money := int(e.get("money", 0))
	if money > 0:
		var fmt := GameData.text("string format_money").strip_edges()
		log_msg("%s %s" % [GameData.text("string combat_picked_up").strip_edges(),
			fmt % money if "%d" in fmt else "%s (%d)" % [fmt, money]])


## texts.res "game_over" / "game_over_msg": load a saved game or leave.
## End of the campaign: the original's credits screen 8 ("Crdt": Outtro1 +
## Crdtfin, the scrolling credits over Crdt.bik, Crdtfout + Outtro2), then the
## main menu.
func _show_ending() -> void:
	_movie.stop()
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_add_ui(layer)
	var c := CreditsPanel.new()
	c.name = "Credits"
	c.screen_name = "Crdt"
	layer.add_child(c)
	c.closed.connect(func(): _on_esc_board("exit"))


## Hero death (single player): sends the client message 9, whose
## handler → the top screen's slot 31 with 0 —
## CInterface3D / village screen: buttons\gameover.wav
## then (manager, "game_over", "game_over_msg", 3, 1) opened
## (box, 1, 1) (frame frozen, single player paused). Results
## opens the Load screen in Load mode
## without the slide-in (= 0, = 0);, and (that
## Load screen closed without loading), go to the main menu (manager = 1
## ). Loading a save needs no result.
func _show_game_over() -> void:
	if MessageBox.is_up(_game_over_box) or _game_over_load:
		return
	dismiss_death_notice()
	GameSound.instance.ui("buttons\\gameover.wav")
	if not _esc_open:
		_open_menu()
	_menu.visible = false
	_game_over_box = MessageBox.ask(self, "game_over", "game_over_msg")
	_game_over_box.process_mode = Node.PROCESS_MODE_ALWAYS
	_game_over_box.answered.connect(func(yes: bool):
		_game_over_box = null
		if yes and game.session.is_host:
			_game_over_load = true
			_save_load.open(false, _esc_frame, false)
		else:
			_on_esc_board("exit"))


## Remake option "sp_death_notice" (Session.hero_died, single player only): at
## the main hero's death the game-over box's sound (buttons\gameover.wav) and
## a small notice at the top (GameOverNotice) with the box's choices — Load
## (✓) and Main menu (✗) — and Hide. No pause; the zone change still opens the
## box (`_show_game_over`, which hides the notice). `hint`: an extra line
## under the message (e.g. that a companion can still revive the hero).
## The notice also hides itself once the main hero lives again (a revival, a
## load: GameOverNotice.still_dead); `dismiss_death_notice` hides it at once.
func show_death_notice(hint := "") -> void:
	if game.session.online or MessageBox.is_up(_game_over_box) or _game_over_load:
		return
	GameSound.instance.ui("buttons\\gameover.wav")
	if _death_notice == null:
		_death_notice = GameOverNotice.new()
		_death_notice.name = "DeathNotice"
		_death_notice.still_dead = game.session.sp_main_hero_dead
		_death_notice.chosen.connect(_on_death_notice)
		_field.add_child(_death_notice)
	_death_notice.hint = hint
	_death_notice.visible = true
	_death_notice.queue_redraw()


func dismiss_death_notice() -> void:
	if _death_notice:
		_death_notice.visible = false


func _on_death_notice(what: String) -> void:
	_death_notice.visible = what == "load"   # a load hides it (still_dead)
	match what:
		"load":   # the Esc menu's Load screen: closing it goes back to the game
			if not _esc_open:
				_open_menu()
			_on_esc_board("load")
		"menu":
			_on_esc_board("exit")


## The "endofgame" string command (the top screen's slot 31
## with 1; CInterface3D): no sound, the ordinary
## message box (manager, "end_of_game", "end_of_game_msg"
## 3, 1) — texts.res "Congratulations!" / "You have finished the
## demo!", a leftover of the demo — opened (box, 1, 1). Its
## results are not handled by the screen (
## knows), so ✓ and ✗ only close
## it. No shipped script sends the command: the campaign ends through
## LeaveToZone("EndofGame") → credits screen 8 (`_show_ending`).
func _show_end_of_game() -> void:
	if MessageBox.is_up(_end_box) or _esc_open:
		return
	_open_menu()   # (box, 1, 1): frame frozen, single player paused
	_menu.visible = false
	_end_box = MessageBox.ask(self, "end_of_game", "end_of_game_msg")
	_end_box.process_mode = Node.PROCESS_MODE_ALWAYS
	_end_box.answered.connect(func(_yes: bool):
		_end_box = null
		_close_menu())


var _end_box: MessageBox


## The leave-zone box (CInterface3D, armed by a move click into a
## zone exit, Session._arm_exit): (manager, "leave_zone"
## "leave_zone_msg", 3, 1) — "Leave Game zone" / "Do you really want
## to leave…" — opened like the end-of-game box (box, 1, 1).
## ✓ = leaves through the exit; ✗ closes.
func _show_leave_box(exit: int) -> void:
	if MessageBox.is_up(_leave_box) or MessageBox.is_up(_end_box) or _esc_open:
		return
	_open_menu()
	_menu.visible = false
	_leave_box = MessageBox.ask(self, "leave_zone", "leave_zone_msg")
	_leave_box.process_mode = Node.PROCESS_MODE_ALWAYS
	_leave_box.answered.connect(func(yes: bool):
		_leave_box = null
		_close_menu()
		if yes:
			game.issue({"t": "leave_exit", "exit": exit}))


var _leave_box: MessageBox


func _show_travel(options: Array, from := "", start: Array = []) -> void:
	_close_travel()
	# Who chooses is unchanged: the party leader (player 0), see Session "travel".
	var leader := game.session.my_index == 0
	var map := TravelMap.new()
	map.setup(game.session, options, leader, from, start)
	if leader:
		map.picked.connect(func(o): game.issue({"t": "travel", "zone": o.zone, "entrance": o.entrance}))
		map.cancelled.connect(func(): game.issue({"t": "travel_cancel"}))
	# Camp button: the original screen 5 with constr_current 0 = the camp without
	# a trader, i.e. the dressing screen (CampView "weapons").
	map.camp.connect(func(): _inventory.open(false))
	map.menu.connect(toggle_menu)
	map.help.connect(_tutorial.show_help)
	map.quick.connect(_travel_quick)
	_travel.add_child(map)
	_travel.visible = true


## Quick save / load on the travel map: single player only.
func _travel_quick(action: String) -> void:
	if game.session.online:
		return
	if action == "quicksave":
		game.session.save_game("quick")
	elif game.session.load_game("quick"):
		_close_travel()
	else:
		log_msg(RemakeText.t("No quick save."))


func _close_travel() -> void:
	for c in _travel.get_children():
		c.queue_free()
	_travel.visible = false


func toggle_inventory() -> void:
	if _inventory.visible and not _inventory.shop_mode:
		_inventory.visible = false
	else:
		_inventory.open(false)


## The quests screen outside the global map (ZoneObjectives "field" /
## "village" mode), or null.
var quests_screen: ZoneObjectives


func open_quests(how: String, zone: String) -> void:
	if quests_screen:
		return
	if how == "field" and _clock_dial:
		# The disc click and the objectives key (
		# case 4) both clear the quest pulse (dial).
		_clock_dial.pulse = false
	quests_screen = ZoneObjectives.new()
	quests_screen.setup(game.session, zone, [], true, how)
	quests_screen.back.connect(func():
		quests_screen.queue_free()
		quests_screen = null)
	_add_ui(quests_screen)


func toggle_side_quests() -> void:
	if _side_quests.visible:
		_side_quests.visible = false
	else:
		_side_quests.open()


func toggle_journal() -> void:
	if _journal.visible:
		_journal.visible = false
	else:
		_journal.open()


func _first_selected() -> GameUnit:
	for u: GameUnit in game.selected if game else []:
		if is_instance_valid(u):
			return u
	return null


## The move dial's pointer (refresh): the gait
## (unit: 0 crawl, 1 kneel, 2 walk, 3 run) when every selected unit
## has the same one, else -2 (no pointer, every sector dim); -1 none selected.
func _selected_gait() -> int:
	var v := -1
	for u: GameUnit in game.selected:
		if is_instance_valid(u):
			var g := u.gait()
			v = g if v == -1 else v if v == g else -2
	return v


## Movement mode: the move dial's sectors (: click.wav, then net
## message 0x35 with the sector's gait for each selected unit
## which also stores it in the local unit at once) and the keyboard.ini
## run / walk / sneak / crawl keys. Nothing happens with nothing selected.
func set_move_mode(mode: String) -> void:
	var g := {"crawl": 0, "sneak": 1, "walk": 2, "run": 3}.get(mode, -1) as int
	if g < 0 or _first_selected() == null:
		return
	if GameSound.instance:
		GameSound.instance.ui("buttons\\battle\\click.wav")
	var ids := game.selected.map(func(s: GameUnit): return s.uid)
	game.issue({"t": "gait", "units": ids, "gait": g})
	if not game.session.is_host:
		for u: GameUnit in game.selected:
			if is_instance_valid(u):
				u.restore_gait(g)   # shown at once; the host's snapshots confirm it
	_rebuild_party()


## Aggressive / Defensive of the selection (dial refresh):
## 1 / 0 when all selected units agree, -2 mixed, -1 nothing selected.
func _selected_aggression() -> int:
	var v := -1
	for u: GameUnit in game.selected:
		if is_instance_valid(u):
			var a := int(u.aggressive)
			v = a if v == -1 else v if v == a else -2
	return v


## The dial's inner disc / key "swarm" (the original): click sound
## all selected units become Defensive when all of them are Aggressive, else
## all Aggressive; each one is a command to the host (net message 0x3b).
func toggle_aggression() -> void:
	if GameSound.instance:
		GameSound.instance.ui("buttons\\battle\\click.wav")
	if game.selected.is_empty():
		return
	var on := _selected_aggression() != 1
	var ids := game.selected.map(func(s: GameUnit): return s.uid)
	game.issue({"t": "aggression", "units": ids, "on": on})
	for u: GameUnit in game.selected:
		u.aggressive = on   # shown at once; the host's snapshots confirm it


func toggle_menu() -> void:
	if _esc_open:
		_close_menu()
	else:
		_open_menu()


##  for the first modal screen over the game: the frame captured
## (state 1) and, in single player only, the game
## paused ((1)) with its pause state kept.
func _open_menu() -> void:
	_esc_open = true
	_esc_frame = null
	if DisplayServer.get_name() != "headless":
		_esc_frame = get_viewport().get_texture().get_image()
	_esc_bg.use(_esc_frame)
	_esc_bg.visible = _esc_frame != null
	_menu.visible = true
	if not game.session.online:
		_pause_before = get_tree().paused
		get_tree().paused = true


## back to the game alone, the frozen frame dropped and the
## pause state restored (single player).
func _close_menu() -> void:
	if not _esc_open:
		return
	_esc_open = false
	_menu.visible = false
	_esc_bg.visible = false
	_esc_bg.texture = null
	_esc_frame = null
	if is_instance_valid(_quit_box):
		_quit_box.queue_free()
	if _pause_before != null:
		get_tree().paused = bool(_pause_before)
		_pause_before = null


## The Esc signpost's boards (click handler: buttons\menu\ok.wav
## then board 0 Save, 1 Load, 2 Return, 3 Exit, 4 Options).
func _on_signpost(action: String) -> void:
	if action != "exit":
		_on_esc_board(action)
		return
	# Board 3: (menu, "quit", "quit_msg", 3, 1)
	# (main menu); ✗ stays in the Esc menu.
	_menu.visible = false
	_quit_box = MessageBox.ask(self, "quit", "quit_msg")
	_quit_box.answered.connect(func(yes: bool):
		_quit_box = null
		if yes:
			_on_esc_board("exit")
		elif _esc_open:
			_menu.visible = true)


## Boards of the original Esc signpost (unmoco1). Save and Load open the
## Load / Save screen (mode 1 / 0, slide- = 1), Options the Options
## screen (slide- = 1), each over the frame captured with the menu
## closing any of them closes the Esc menu too. the original offers
## Save and Load only outside network games; the remake lets
## the co-op host save and load (its own feature).
func _on_esc_board(action: String) -> void:
	match action:
		"resume":
			_close_menu()
		"options":
			_menu.visible = false
			_options.open(_esc_frame, true)
		"save":
			if not game.session.is_host:
				log_msg(RemakeText.t("Only the host can save"))
				return
			_menu.visible = false
			_save_load.open(true, _esc_frame, true, game.session.fresh_save_entry(_esc_frame))
		"load":
			if not game.session.is_host:
				log_msg(RemakeText.t("Only the host can load"))
				return
			_menu.visible = false
			_save_load.open(false, _esc_frame, true)
		"exit":
			_close_menu()
			var main := get_tree().current_scene
			if main and main.has_method("back_to_menu"):
				main.call_deferred("back_to_menu")
			else:
				get_tree().quit()


func blocks_input() -> bool:
	return _esc_open or _menu.visible or _dialog.visible or _travel.visible or (TouchInput.enabled and _panel_open())


## Polling the keyboard bypasses GUI event consumption, so the camera must
## explicitly stop behind panels, including co-op panels that do not pause.
func blocks_camera() -> bool:
	return blocks_input() or _panel_open()


func _panel_open() -> bool:
	if quests_screen != null:
		return true
	for panel in [_inventory, _journal, _side_quests, _tutorial, _movie, _options, _save_load,
			_game_over_box, _quit_box]:
		if is_instance_valid(panel) and panel.visible:
			return true
	return false


func _add_ui(child: Node) -> void:
	if child is Control:
		_safe_root.add_child(child)
	else:
		add_child(child)

func ui_size() -> Vector2:
	return _safe_root.size if is_instance_valid(_safe_root) else get_viewport().get_visible_rect().size

func _layout_safe_area() -> void:
	var screen := get_viewport().get_visible_rect().size
	var safe := Portability.safe_rect(screen) if TouchInput.enabled else Rect2(Vector2.ZERO, screen)
	# Reanchor the original HUD inside the usable rectangle without stretching
	# its artwork or its 3D previews in either direction.
	_safe_root.position = safe.position
	_safe_root.size = safe.size
