class_name PlayerList
extends Control
## Remake-only co-op player list (NetStatus): one line per player — name in
## the player's chat colour, ping, status (textslmp lmp_status_*) — under the
## minimap, right-aligned at 800×600 x 795, from y 170, scaled by the window
## height. Shown only in an online game. (The original shows the players'
## status only on a network game's village screen, and ping
## only in the server browser; see NetStatus.)
## The co-op host can click it to open its player list with Kick / Ban
## (PlayersPanel, remake).

var game: Game
var _sig := ""


var _box := Rect2()   # the drawn list (host: a click opens PlayersPanel)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "


func _host() -> bool:
	return game != null and game.session != null and game.session.online and game.session.is_host


func _has_point(point: Vector2) -> bool:
	return visible and _host() and _box.has_point(point)


func _get_tooltip(_at: Vector2) -> String:
	return RemakeText.t("The players in this game; remove a player.")


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		game.hud.open_players()


func _process(_dt: float) -> void:
	var s := game.session if game else null
	# Not over a movie (the co-op intro plays once the first zone is built).
	var on := s != null and s.online and not (game.hud and game.hud._movie and game.hud._movie.visible)
	visible = on
	if not on:
		return
	var sig := "%s|%s|%s" % [s.players, s.net.status, Interface800.canvas_size(self)]
	if sig != _sig:
		_sig = sig
		queue_redraw()


func lines() -> Array:
	var s := game.session
	var out := []
	var pids := s.players.keys()
	pids.sort_custom(func(a, b): return int(s.players[a].index) < int(s.players[b].index))
	for pid in pids:
		var p: Dictionary = s.players[pid]
		var st: Dictionary = s.net.status.get(pid, {})
		var ping := "" if int(pid) == 1 or String(st.get("state", "connect")) == "connect" else "%d ms" % int(st.get("ping", 0))
		out.append([String(p.name), NetStatus.colour(int(p.index)), ping, NetStatus.state_text(String(st.get("state", "connect")))])
	return out


func _draw() -> void:
	var k := Interface800.canvas_size(self).y / 600.0
	var right := Interface800.canvas_size(self).x - 5.0 * k
	var f := DialogPanel.font()
	var fs := int(round(12.0 * k))
	var y := 170.0 * k
	var rows := lines()
	if rows.is_empty():
		return
	# The status column takes its longest text ("Connection problems"), the
	# list growing leftwards from the 185-unit minimum.
	var sw := 56.0 * k
	for r: Array in rows:
		sw = maxf(sw, f.get_string_size(r[3], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 2.0 * k)
	var extra := sw - 56.0 * k
	_box = Rect2(right - 185.0 * k - extra, y - 2.0 * k, 185.0 * k + extra, (rows.size() * 15.0 + 4.0) * k)
	draw_rect(_box, Color(0, 0, 0, 0.45))
	for r: Array in rows:
		var base := y + 12.0 * k
		draw_string(f, Vector2(right - 180.0 * k - extra, base), r[0], HORIZONTAL_ALIGNMENT_LEFT, 75.0 * k, fs, r[1])
		draw_string(f, Vector2(right - 103.0 * k - extra, base), r[2], HORIZONTAL_ALIGNMENT_RIGHT, 40.0 * k, fs, DialogPanel.TEXT_COLOR)
		draw_string(f, Vector2(right - 58.0 * k - extra, base), r[3], HORIZONTAL_ALIGNMENT_LEFT, sw, fs, DialogPanel.TEXT_COLOR)
		y += 15.0 * k
