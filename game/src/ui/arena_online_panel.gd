class_name ArenaOnlinePanel
extends NetworkPanel
## Reuses the co-op screen's frames, rows, address copy/paste, keyboard,
## touch editing, gamepad targets and confirm/back controls.
signal ready_requested
var connection: ArenaOnlineSession
var port_text := str(ArenaOnlineSession.PORT)
const ONLINE_BOOK := "user://autochess-addresses.cfg"

func _ready() -> void:
	campaign_only = true
	super._ready()
	lan.discovery_port = ArenaOnlineSession.LAN_PORT
	lan.protocol = ArenaOnlineSession.PROTOCOL
	lan.modes = PackedStringArray(["autochess"])
	_setup_button.hide()
	max_players = 9

func _refresh_start_saves() -> void: pass
func _rebuild_save_choices() -> void: pass
func _sync_save_choice() -> void:
	if _save_choice: _save_choice.hide()
func _discovery_protocol() -> int: return ArenaOnlineSession.PROTOCOL
func _island(_g: Dictionary) -> String: return RemakeText.t("Autochess")
func _book_game(a: String) -> Dictionary:
	if not _lan_on(): return {}
	var hp := Session.parse_address(a.trim_prefix("ws://").trim_prefix("wss://"), ArenaOnlineSession.PORT)
	return lan.game_at(String(hp[0]), int(hp[1]))
func _on_off(on: bool) -> String:
	return RemakeText.t("On") if on else RemakeText.t("Off")

func _load_book() -> void:
	var config := ConfigFile.new()
	if config.load(ONLINE_BOOK) == OK: addresses = PackedStringArray(config.get_value("book","addresses",PackedStringArray()))
func _save_book() -> void:
	var config := ConfigFile.new(); config.set_value("book","addresses",addresses); config.save(ONLINE_BOOK)

func _mode_title(p: int) -> String:
	if p == HOST_COOP: return RemakeText.t("Host autochess")
	if p == JOIN_COOP: return RemakeText.t("Join autochess")
	return RemakeText.t("Online autochess")
func _mode_desc(p: int) -> String:
	return RemakeText.t("Create a tournament and share your address with friends.") if p == HOST_COOP else RemakeText.t("Enter a friend's address and compete with your own army.")
func _page_desc() -> String:
	return RemakeText.t("Host or join a nine-player tournament. Computers fill empty seats.")
func _address_placeholder() -> String:
	return RemakeText.t("e.g. wss://example.org/game") if _web() else RemakeText.t("e.g. 192.168.1.20:27016")
func _addr_hint() -> String:
	return RemakeText.t("Enter the host's public address or a LAN/VPN address. Browser players need a secure WebSocket address.")

func _rows() -> Array:
	var locked := hosting or joining
	var rows := [{"id":"name","kind":"edit","label":RemakeText.t("Your name"),"value":player_name,"on":not locked,"hint":RemakeText.t("Your name in the autochess tournament.")}]
	if page == JOIN_COOP:
		rows.append({"id":"addr","kind":"edit","label":RemakeText.t("Host's address"),"value":address,"on":not locked,"hint":_addr_hint()})
	rows.append({"id":"password","kind":"edit","label":pw_label(),"value":password if page == HOST_COOP else join_password,"on":not locked,"hint":_pw_hint(page == HOST_COOP)})
	if page == HOST_COOP:
		rows.append({"id":"port","kind":"edit","label":RemakeText.t("Port"),"value":port_text,"on":not locked,"hint":RemakeText.t("The host listens on this port. Include it in the join address.")})
		rows.append({"id":"upnp","kind":"switch","label":RemakeText.t(GameData.REMAKE_OPTIONS.net_upnp[0]),"value":_on_off(GameData.option("net_upnp")==1),"on":not locked,"hint":RemakeText.t("Asks your router to let friends in from the internet (UPnP / NAT-PMP / PCP). Leave it on.")})
		rows.append({"id":"websocket","kind":"switch","label":RemakeText.t("WebSocket (for browser players)"),"value":_on_off(GameData.option("net_websocket")!=0),"on":not locked,"hint":RemakeText.t("Leave this off unless a friend plays the browser version. Browser players can only reach a secure wss:// address, which needs an HTTPS proxy in front of this port. With it on, the others join with ws://address:port, and the router is not opened automatically (forward TCP port %d by hand).") % int(port_text)})
	return rows

func _activate(id: String, dir := 0) -> void:
	if id == "port":
		_focus = "port"; _caret_t = 0
		if TouchInput.enabled: TouchTextEdit.open(self,port_text,5,func(value): port_text=value; queue_redraw(),"Port")
		return
	super._activate(id,dir)
func _type(character: String, back := false) -> void:
	if _focus == "port" and _row_on("port"):
		if back: port_text = port_text.left(maxi(0,port_text.length()-1))
		elif character.is_valid_int(): port_text=(port_text+character).left(5)
	else: super._type(character,back)

func _draw() -> void:
	_targets.clear()
	_block(STATUS_RECT,_status_text(),0,TEXT,3)
	if page == MODES: _draw_modes()
	else: _draw_page()
	_draw_buttons()
	_draw_pad_glyphs()

func _draw_modes() -> void:
	panel(Rect2(100,120,600,380))
	text(Rect2(100,142,600,28),RemakeText.t("Online autochess"),2,TEXT,HORIZONTAL_ALIGNMENT_CENTER)
	_block(Rect2(120,180,560,56),_page_desc(),1,GREY,3,HORIZONTAL_ALIGNMENT_CENTER)
	for index in 2:
		var p := HOST_COOP if index == 0 else JOIN_COOP
		var rect := Rect2(110,258+index*90,580,76)
		_targets["mode:"+PAGE_NAMES[p]]=rect
		if _sel == index: draw_rect(r8(rect),BAR)
		var off := _mode_off(p)
		var plate := Rect2(120,rect.position.y+24,190,24)
		sprite(tex("saveload"),plate,PLATE_UV,Color.WHITE if off.is_empty() else Color(0.5,0.5,0.5))
		text_vc(plate,_mode_title(p),1,TEXT if off.is_empty() else GREY,HORIZONTAL_ALIGNMENT_CENTER)
		_block(Rect2(326,rect.position.y+12,352,60),_mode_desc(p) if off.is_empty() else off,1,TEXT if off.is_empty() else GREY,3)

func _draw_friends() -> void:
	var port := int(port_text)
	text(Rect2(110,334,340,20),RemakeText.t("Port: %d") % port + (" (TCP)" if GameData.option("net_websocket") else " (UDP)"),1,TEXT)
	if not hosting:
		_block(Rect2(110,360,340,128),RemakeText.t("Press “Start hosting”. The addresses to give your friends appear here; they choose “%s” and type one of them.") % RemakeText.t("Join autochess"),0,TEXT,6)
		_block(Rect2(460,338,230,148),RemakeText.t("Wait for all human players to be ready. Empty seats become computers."),1,GREY,7)
		return
	if Time.get_ticks_msec() >= _share_t:
		_share_t=Time.get_ticks_msec()+1000; _share=_share_addresses()
	var y:=360.0
	if _share.is_empty():
		y += _block(Rect2(110,y,340,40),RemakeText.t("No network address found. Check that this device is connected to a network."),0,ORANGE,2)
	for index in _share.size():
		var address_row:Array=_share[index]
		text(Rect2(110,y+2,78,18),String(address_row[1]),0,GREY)
		text(Rect2(190,y+2,196,20),_fit_line(String(address_row[0]),196,1),1,YELLOW)
		_plate("copy:%d"%index,Rect2(390,y+1,60,19),RemakeText.t("Copy"));y+=22
	var router:=_router_text()
	_block(Rect2(110,y+2,340,LOW.end.y-y-6),router[0],0,router[1],6)
	_roster(460,334,230)

func _roster(x: float, y: float, width: float) -> void:
	var humans := connection.members.size() if connection else 0
	text(Rect2(x,y,width,20),RemakeText.t("Players: %d / %d") % [humans,9],1,TEXT)
	y+=22
	for seat in 9:
		var member:Dictionary={}
		if connection:
			for entry:Dictionary in connection.members.values():
				if int(entry.seat)==seat: member=entry;break
		var title := RemakeText.t("Computer") if member.is_empty() else String(member.name)
		var ready_text := "" if member.is_empty() else RemakeText.t("Ready" if member.ready else "Not ready")
		text(Rect2(x+4,y,width*0.6-4,16),_fit_line("%d. %s"%[seat+1,title],width*0.6-4,0),0,ORANGE if not member.is_empty() else GREY)
		text(Rect2(x+width*0.6,y,width*0.4,16),ready_text,0,GREEN if member.get("ready",false) else GREY,HORIZONTAL_ALIGNMENT_RIGHT)
		y+=15

func _draw_join_low() -> void:
	if not joining: super._draw_join_low();return
	_roster(110,334,340)
	_block(Rect2(470,338,218,70),RemakeText.t("Connected to %s. Waiting for the host to start the game.") % selected_address() if connection and connection.my_seat>=0 else RemakeText.t("Connecting…"),0,TEXT,4)
	_block(Rect2(470,414,218,76),RemakeText.t("Wait for all human players to be ready. Empty seats become computers."),0,GREY,5)

func _ok_label() -> String:
	if page == JOIN_COOP and joining and connection and connection.my_seat>=0:
		var mine:Dictionary=connection.members.get(connection.peer.get_unique_id(),{}) if connection.peer else {}
		return RemakeText.t("Not ready" if mine.get("ready",false) else "Ready")
	return super._ok_label()
func _ok_enabled() -> bool:
	if hosting: return connection != null and connection.owns_game() and not connection.members.values().any(func(member):return not member.ready)
	if joining: return connection != null and connection.peer != null and connection.my_seat>=0
	return super._ok_enabled()
func _primary() -> void:
	if joining:
		if _ok_enabled():ready_requested.emit()
		return
	super._primary()
