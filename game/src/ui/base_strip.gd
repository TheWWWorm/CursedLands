class_name BaseStrip
extends Control
## The original multiplayer game's player strip on the base (village) screen.
##
## the original (traced 2026-10-04): in a network game the village screen builds
## a widget over (464,0)-(800,160) with a text
## surface (464,75)-(800,105). rebuilds its cells
## from the player list, this computer's player first:
## a cell is 56 px wide, the first at x 744..800, the next ones leftwards
## (: x 744 − 56k.. 800 − 56k, click rect y 0..80), with the
## player's interface face "infa<model>…face" / "face%s%02d" at the cell's
## centre x, y 32, depth 7, scale 0.3, turned 3.2986 rad about x. Its draw
##  writes per cell, white, font 0, centred in the 56 px: line 1
## (y 0..15 of the surface, so 75..90) the player's state — 0 «lmp_status_zone»
## On map, 1 «lmp_status_base» On Base, 2 «lmp_status_camp» Trading, 3 / 4
## «lmp_status_connect» Enters —, line 2 (90..105) the swap state:
## «lmp_exch_we_offer» Swap! when this player's offer is to that
## player, «lmp_exch_they_offer» Swap? when that player offers one to us
## . The strip is not drawn while a swap screen is open.
##
## Remake: the cells as above, the face by `Portrait` (the hero's own head when
## its interface face is missing), the state from NetStatus (the host's status
## each second; "camp" while the player's trader screen is open, "lag" is the
## remake's «Connection problems»). Shown in the multiplayer game's base only.
## Swap (PlayerSwap): line 2 as the original's; a left press on a cell (input
##   =, click rect y 0..80) plays
## buttons\battle\on_off.wav and, on another player's cell, withdraws our
## offer when it goes to that player, else offers that player
## a swap. The strip hides while the swap screen (an
## InventoryPanel screen) is up.
## Remake co-op (not in the original, whose campaign has no swap): the same
## strip in a village while another player keeps their own bag and purse
## (PlayerSwap.can_swap_with: a hero brought from a single-player save); a
## press on a cell whose player shares this computer's bag does nothing.
## **Approx.**: other branch (manager = 1 / 2: the server's kick / ban by face
##  commands 4 / 5) is not ported.

const CELL := 56.0
const FIRST_X := 744.0
const FACE_Y := 32.0
const FACE_SCALE := 0.3
const TEXT_Y := 75.0

var game: Game
var _cells: Array = []    # [pid, Portrait, unit]
var _sig := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


## Only the cells take the mouse (click rects).
func _has_point(point: Vector2) -> bool:
	return visible and cell_at(point) >= 0


## The strip position under local point `local`, or -1.
func cell_at(local: Vector2) -> int:
	var vs := Interface800.canvas_size(self)
	var k := _k()
	var p := Vector2(800.0 - (vs.x - local.x) / k, local.y / k)
	for i in _cells.size():
		if cell(i).has_point(p):
			return i
	return -1


func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	var i := cell_at(e.position)
	if i < 0:
		return
	accept_event()
	press_cell(i)


##  for strip position `i`.
func press_cell(i: int) -> void:
	if GameSound.instance:
		GameSound.instance.ui("buttons\\battle\\on_off.wav")
	var s := game.session
	var pid := int(_cells[i][0])
	if not s.players.has(pid):
		return
	var idx := int(s.players[pid].index)
	if idx == s.my_index or not s.swap.can_swap_with(idx):
		return
	if s.swap.we_offer(idx):
		s.swap.send({"t": "withdraw"})
	else:
		s.swap.send({"t": "request", "to": idx})


## Line 2 of player `pid`: «Swap?» when that player offers us a swap (it wins,
## written last), else «Swap!» when ours goes to that player.
func swap_text(pid: int) -> String:
	var s := game.session
	if not s.players.has(pid):
		return ""
	var idx := int(s.players[pid].index)
	if s.swap.they_offer(idx):
		return NetStatus.lmp_text("lmp_exch_they_offer", "", "Swap?")
	if s.swap.we_offer(idx):
		return NetStatus.lmp_text("lmp_exch_we_offer", "", "Swap!")
	return ""


## True in the multiplayer game's base (a "brief" zone of LmpMode).
func wanted() -> bool:
	var s := game.session if game else null
	if s == null or not s.multiplayer_game or game.world == null or s.campaign == null:
		return false
	if s.lmp.is_empty() and not _coop_swap():
		return false
	var peer := s.multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false   # the connection is gone (players() asks the peer for its id)
	if String(s.campaign.zone(s.zone_id).get("type", "")) != "brief":
		return false
	var hud := game.hud
	if hud and ((hud._movie and hud._movie.visible) or (hud._inventory and hud._inventory.visible)):
		return false
	return true


## The players in strip order: this computer's first, then by player slot.
func players() -> Array:
	var s := game.session
	var me := s.multiplayer.get_unique_id()
	var pids := s.players.keys()
	pids.sort_custom(func(a, b):
		if int(a) == me or int(b) == me:
			return int(a) == me
		return int(s.players[a].index) < int(s.players[b].index))
	return pids


## Co-op: some other player can swap with this computer's.
func _coop_swap() -> bool:
	var s := game.session
	if s.swap == null:
		return false
	for pid in s.players:
		var idx := int(s.players[pid].index)
		if idx != s.my_index and s.swap.can_swap_with(idx):
			return true
	return false


## The 800×600 cell of strip position `i`.
static func cell(i: int) -> Rect2:
	return Rect2(FIRST_X - CELL * i, 0, CELL, 80)


func _hero_of(index: int) -> GameUnit:
	for u: GameUnit in game.world.units.values():
		if u.controller == index and u.has_meta("hero") and is_instance_valid(u):
			return u
	return null


## The state line of player `pid` (textslmp lmp_status_*).
func state_text(pid: int) -> String:
	var st: Dictionary = game.session.net.status.get(pid, {})
	return NetStatus.state_text(String(st.get("state", "connect")))


func _k() -> float:
	return Interface800.canvas_size(self).y / 600.0


## 800×600 -> local: the strip keeps to the window's right edge.
func _p(v: Vector2) -> Vector2:
	var vs := Interface800.canvas_size(self)
	return Vector2(vs.x - (800.0 - v.x) * _k(), v.y * _k())


func _process(_dt: float) -> void:
	var game_trading := false
	if game and game.hud and game.hud._inventory:
		var inv = game.hud._inventory
		game_trading = inv.visible and inv._camp.visible and int(inv._camp.shop_id) != 0
	if game and game.session and game.session.multiplayer_game:
		game.session.net.set_trading(game_trading)
	var on := wanted()
	visible = on
	if not on:
		if not _cells.is_empty():
			_clear()
		return
	var pids := players()
	var units := []
	for pid in pids:
		units.append(_hero_of(int(game.session.players[pid].index)))
	var sig := ",".join(pids.map(func(p): return str(p))) + "|" + ",".join(units.map(func(u): return str(u.uid) if u else "-"))
	if sig != _sig:
		_clear()
		_sig = sig
		for i in pids.size():
			var p: Portrait = null
			if units[i]:
				p = Portrait.new()
				p.view_size = Vector2i(56, 80)
				p.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(p)
				p.show_unit(units[i])
			_cells.append([pids[i], p, units[i]])
	for i in _cells.size():
		var p: Portrait = _cells[i][1]
		if p == null:
			continue
		var r := cell(i)
		var face := Rect2(r.position.x, 0, CELL, TEXT_Y)
		p.position = _p(face.position)
		p.size = face.size * _k()
		# FUN608f50: x-axis angle, distinct from HUD faces' PI.
		p.set_exe_place(face, r.get_center().x, FACE_SCALE, FACE_Y, 3.2986721992492676)
	queue_redraw()


func _clear() -> void:
	for c in _cells:
		if c[1]:
			(c[1] as Portrait).queue_free()
	_cells.clear()
	_sig = ""


func _draw() -> void:
	if _cells.is_empty():
		return
	var f := DialogPanel.font()
	var k := _k()
	var fs := int(round(Interface800.FONT_EM[0] * 800.0 * k))
	for i in _cells.size():
		var r := cell(i)
		var pid := int(_cells[i][0])
		# Line 1 (y 75..90): the state; line 2 (90..105): the swap state.
		for line in [[state_text(pid), TEXT_Y], [swap_text(pid), TEXT_Y + 15.0]]:
			var t: String = line[0]
			if t.is_empty():
				continue
			var a := _p(Vector2(r.position.x, line[1]))
			var ls := fs
			var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, ls).x
			# Longer remake states («Connection problems») shrink to stay inside the cell.
			if w > CELL * k * 0.96:
				ls = maxi(6, int(fs * CELL * k * 0.96 / w))
				w = f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, ls).x
			var base := a.y + (15.0 * k + ls * 0.7) * 0.5
			draw_string(f, Vector2(a.x + (CELL * k - w) * 0.5 + k, base + k), t, HORIZONTAL_ALIGNMENT_LEFT, -1, ls, Interface800.SHADOW)
			draw_string(f, Vector2(a.x + (CELL * k - w) * 0.5, base), t, HORIZONTAL_ALIGNMENT_LEFT, -1, ls, Color.WHITE)
