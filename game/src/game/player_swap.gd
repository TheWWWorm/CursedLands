class_name PlayerSwap
extends Node
## The original multiplayer game's "player swap": two players exchange items
## from their bags and money (the original, traced 2026-10-04; details
##
## the original: every player has at most one offer (a network object, client
## ): , to, items, money
## agreed, the revision of the partner's offer it agreed to
## its own revision (1 when made, +1 at each change) and "paired"
## (set by the server). A click on another player's face in the base
## strip makes an offer to that player (replacing
## an offer to someone else) or, when ours already goes to that player,
## withdraws it. The server pairs two offers
## that point at each other — both swap screens open (screen 9, from the
## strip's draw) — else tells the target «lmp_trade_requested».
## Changing an offer (: items put into / taken out of the offer
## pile, the money typed) bumps its revision and clears its agreement; the
## partner's client clears its own agreement when the changed offer arrives
## . ✓ (area 0) agrees when the
## money offered is at most the player's money (records the
## partner's revision), ✗ (area 1) takes it back, Exit / Esc
## withdraws the offer. The server commits when both agreed
## each to the other's current revision. A withdrawn offer that was never
## paired tells its target «lmp_trade_canceled»; a paired one
## ends the swap for both (: the partner's offer goes too).
##
## Remake (host-authoritative): the host keeps every offer and sends the whole
## table to all peers after each change (`_rpc_offers`); clients send their
## clicks as commands (`send`). The original moves the items on each client
## the snapshot it took when agreeing (: bag =
## snapshot + received, money = money − offered + received); here the host
## moves items from the bag into the offer as each pile changes, and commits
## both offers at once. A withdrawn offer returns its items to the same bag,
## including after a lost connection or a zone change. Money is checked on
## agreement and commit; it stays in the purse until the trade commits.
## Campaign quest items are not offered (the remake keeps them in one list for the
## whole party, not in a player's bag).
## Co-op campaign (remake): the same between two players whose bags differ (a
## joiner who brought its hero has its own, CoopProgress.purse_entry; the host
## and co-op class heroes share the campaign's), in a village or the map's camp.

signal changed
## A line for this player (textslmp key, the other player's name).
signal note(text: String)

## each pile has 8 cells.
const PILE := 8
## (…, 9, …): the money field takes 9 characters.
const MONEY_DIGITS := 9
const MONEY_MAX := 999999999

var session: Session
## player slot -> {to, items, money, agreed, rev, ack, paired} (every peer).
var offers := {}
## player slot -> its bag's key ("campaign" or "p<slot>"), from the host.
var keys := {}
var _zone := ""
## Host-only bag references: an offer returns to its original purse even if
## the player disconnects or the campaign state is about to change.
var _escrow_bags := {}


func _ready() -> void:
	session.players_changed.connect(_on_players_changed)


# ---------------------------------------------------------------- queries

func mine() -> Dictionary:
	return offers.get(session.my_index, {})


## The player this peer is swapping with (both offers point at each other), or -1.
func partner() -> int:
	var m := mine()
	if m.is_empty() or not bool(m.get("paired", false)):
		return -1
	var other: Dictionary = offers.get(int(m.to), {})
	return int(m.to) if not other.is_empty() and int(other.to) == session.my_index else -1


func partner_offer() -> Dictionary:
	var p := partner()
	return offers.get(p, {}) if p >= 0 else {}


## Our offer goes to `idx` (the strip's «Swap!»).
func we_offer(idx: int) -> bool:
	var m := mine()
	return not m.is_empty() and int(m.to) == idx


## `idx` offers us a swap (the strip's «Swap?»).
func they_offer(idx: int) -> bool:
	var o: Dictionary = offers.get(idx, {})
	return not o.is_empty() and int(o.to) == session.my_index


## Players `a` and `b` have bags of their own (the remake's co-op heroes may
## share the campaign's), so a swap between them moves something.
func separate_bags(a: int, b: int) -> bool:
	if a == b:
		return false
	if not session.lmp.is_empty():
		return true
	return String(keys.get(a, "campaign")) != String(keys.get(b, "campaign"))


## Where a swap can start: the multiplayer game's base (the strip is the base
## screen's), or in the co-op campaign a village or the map's camp.
func place_ok() -> bool:
	if session.world == null or not session.online:
		return false
	if not session.lmp.is_empty():
		if session.lmp_travel:
			var w: GameWorld = session.lmp_travel.owner_world(session.my_index)
			return w != null and String(w.zone.get("type", "")) == "brief"
		return session.shop_available()
	return session.camp_available()


func _place_for(player: int) -> bool:
	if session.lmp_travel:
		var w: GameWorld = session.lmp_travel.owner_world(player)
		return w != null and String(w.zone.get("type", "")) == "brief"
	return place_ok()


func can_swap_with(idx: int) -> bool:
	return place_ok() and session.players_include(idx) and session.players_same_zone(session.my_index, idx) \
		and separate_bags(session.my_index, idx)


# ---------------------------------------------------------------- commands

## This peer's command: "request" {to}, "withdraw", "set" {items, money},
## "agree" {rev}, "disagree".
func send(cmd: Dictionary) -> void:
	if not session.lmp.is_empty():
		cmd = cmd.duplicate()
		cmd._zone = session.zone_id
		cmd._generation = session.lmp_generation
	if session.is_host:
		command(cmd, session.my_index)
	else:
		_rpc_cmd.rpc_id(1, cmd)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_cmd(cmd: Dictionary) -> void:
	if not session.is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if session.players.has(pid):
		if session.lmp_travel and not session.lmp_travel.accepts(int(session.players[pid].index),
				String(cmd.get("_zone", "")), int(cmd.get("_generation", 0))):
			return
		command(cmd, int(session.players[pid].index))


## Host: player `player`'s command.
func command(cmd: Dictionary, player: int) -> void:
	if not session.is_host or session.coop.purse_active():
		return
	match String(cmd.get("t", "")):
		"request":
			_request(player, int(cmd.get("to", -1)))
		"withdraw":
			if offers.has(player):
				_remove(player)
				_publish()
		"set":
			_set_offer(player, cmd)
		"agree":
			_agree(player, int(cmd.get("rev", -1)))
		"disagree":
			# only the flag; the revision stays.
			var o: Dictionary = offers.get(player, {})
			if not o.is_empty() and bool(o.agreed):
				o.agreed = false
				_publish()


##  (a new offer to `to`, an older one to someone
## else withdrawn), then the server's.
func _request(player: int, to: int) -> void:
	if to == player or not session.players_include(to) or not session.players_include(player) \
			or not _place_for(player) or not session.players_same_zone(player, to) or not _separate_on_host(player, to):
		return
	var old: Dictionary = offers.get(player, {})
	if not old.is_empty():
		if int(old.to) == to:
			return
		_remove(player)
	offers[player] = {"to": to, "items": [], "money": 0, "agreed": false, "rev": 1, "ack": 0, "paired": false}
	var back: Dictionary = offers.get(to, {})
	if not back.is_empty() and int(back.to) == player:
		offers[player].paired = true
		back.paired = true
	else:
		_note(to, "lmp_trade_requested", _name(player))
	_publish()


## the offer's items and money; its revision moves on and both
## agreements go (the partner's client clears its own).
func _set_offer(player: int, cmd: Dictionary) -> void:
	var o: Dictionary = offers.get(player, {})
	if o.is_empty() or not bool(o.paired):
		return
	var items: Array = []
	var raw = cmd.get("items", [])
	if raw is Array:
		for it in raw:
			if it is String and items.size() < PILE:
				items.append(it)
	var mv = cmd.get("money", 0)
	var money := clampi(int(mv) if mv is int or mv is float else 0, 0, MONEY_MAX)
	var bag := _bag(player)
	var available := bag.duplicate()
	available.append_array(o.items)
	if not _has_items(available, items):
		_publish()   # refused: the client's piles follow the host's table again
		return
	if items == o.items and money == int(o.money):
		return
	if items != o.items:
		# these copies are in the offer box, unavailable for
		# equipping, selling or another command while the offer is open.
		bag.append_array(o.items)
		for it in items:
			bag.remove_at(bag.find(it))
		_escrow_bags[player] = bag
		session.mark_dirty()
		session.sync_state()
	o.items = items
	o.money = money
	o.rev = int(o.rev) + 1
	o.agreed = false
	var other: Dictionary = offers.get(int(o.to), {})
	if not other.is_empty():
		other.agreed = false
	_publish()


##  area 0 /: agree to the partner's offer revision
## `rev` (as this player saw it) when its own money covers what it offers.
func _agree(player: int, rev: int) -> void:
	var o: Dictionary = offers.get(player, {})
	if o.is_empty() or bool(o.agreed) or not bool(o.paired):
		return
	var other: Dictionary = offers.get(int(o.to), {})
	if other.is_empty() or int(other.to) != player or rev != int(other.rev):
		return
	if int(o.money) > _money(player):
		return
	o.agreed = true
	o.ack = rev
	# both agreed, each to the other's current revision.
	if bool(other.agreed) and int(other.ack) == int(o.rev) and int(o.ack) == int(other.rev):
		_commit(player, int(o.to))
		return
	_publish()


## The swap itself, both sides at once (on each original client:
## money − offered + received, the bag without what it gave plus what it got).
func _commit(a: int, b: int) -> void:
	var oa: Dictionary = offers[a]
	var ob: Dictionary = offers[b]
	var bag_a := _bag(a)
	var bag_b := _bag(b)
	var ok := int(oa.money) <= _money(a) and int(ob.money) <= _money(b) and not is_same(bag_a, bag_b)
	if not ok:
		_return_items(a, oa)
		_return_items(b, ob)
	offers.erase(a)
	offers.erase(b)
	_escrow_bags.erase(a)
	_escrow_bags.erase(b)
	if not ok:
		var t := RemakeText.t("The swap was cancelled.")
		_note_text(a, t)
		_note_text(b, t)
		session.sync_state()
		_publish()
		return
	bag_a.append_array(ob.items)
	bag_b.append_array(oa.items)
	var ma := _money(a)
	var mb := _money(b)
	_set_money(a, ma - int(oa.money) + int(ob.money))
	_set_money(b, mb - int(ob.money) + int(oa.money))
	GameData.trace("swap %d <-> %d: %s + %d / %s + %d" % [a, b, oa.items, oa.money, ob.items, ob.money])
	session.mark_dirty()
	session.sync_state()
	_publish()


##  on the host: an offer goes. Never paired: its target hears
## «lmp_trade_canceled»; paired: the partner's offer goes too.
func _remove(player: int) -> void:
	var o: Dictionary = offers.get(player, {})
	if o.is_empty():
		return
	_return_items(player, o)
	offers.erase(player)
	var to := int(o.to)
	if not bool(o.paired):
		if session.players_include(to) and session.players_include(player):
			_note(to, "lmp_trade_canceled", _name(player))
		session.sync_state()
		return
	var back: Dictionary = offers.get(to, {})
	if not back.is_empty() and int(back.to) == player:
		_return_items(to, back)
		offers.erase(to)
	session.sync_state()


func _return_items(player: int, offer: Dictionary) -> void:
	var bag: Array = _escrow_bags.get(player, _bag(player))
	bag.append_array(offer.get("items", []))
	_escrow_bags.erase(player)
	session.mark_dirty()


## A zone change, save or load ends open offers before any purse is captured
## or replaced. Returning the original copies cannot duplicate a committed
## trade: that trade has already removed both offers and escrow references.
func cancel_all() -> void:
	if not session.is_host or offers.is_empty():
		return
	for idx in offers:
		_return_items(int(idx), offers[idx])
	offers.clear()
	session.sync_state()
	_publish()


## Independent LMP departure cancels only this owner's exchange. A third
## player trading with someone else in the base keeps its own offer.
func cancel_player(player: int) -> void:
	if not session.is_host:
		return
	var changed := false
	for idx in offers.keys():
		var offer: Dictionary = offers.get(idx, {})
		if not offer.is_empty() and (int(idx) == player or int(offer.to) == player):
			_remove(int(idx))
			changed = true
	if changed:
		_publish()


## Host: offers of players who left, or to them, go; a zone change ends all.
func _on_players_changed() -> void:
	if not session.is_host:
		return
	var gone := false
	for idx in offers.keys():
		var o: Dictionary = offers.get(idx, {})
		if o.is_empty():
			continue
		if not session.players_include(int(idx)) or not session.players_include(int(o.to)):
			_remove(int(idx))
			gone = true
	if gone or session.online:
		_publish()


func _process(_dt: float) -> void:
	if session == null or not session.is_host:
		return
	if session.lmp_travel:
		return   # the coordinator cancels only the departing owner's exchange
	if session.zone_id != _zone:
		_zone = session.zone_id
		cancel_all()


# ---------------------------------------------------------------- host purses

func _separate_on_host(a: int, b: int) -> bool:
	if not session.lmp.is_empty():
		return a != b
	return _key(a) != _key(b)


func _key(idx: int) -> String:
	return "campaign" if session.coop.purse_entry(idx).is_empty() else "p%d" % idx


func _bag(idx: int) -> Array:
	return session.coop.bag_of(idx)


func _money(idx: int) -> int:
	var e := session.coop.purse_entry(idx)
	return session.state.money if e.is_empty() else int(e.purse.get("money", 0))


func _set_money(idx: int, v: int) -> void:
	var e := session.coop.purse_entry(idx)
	if e.is_empty():
		session.state.money = v
	else:
		e.purse.money = v


## `items` (a multiset of exact bag strings) all lie in `bag`.
static func _has_items(bag: Array, items: Array) -> bool:
	var left := {}
	for it in bag:
		left[it] = int(left.get(it, 0)) + 1
	for it in items:
		if int(left.get(it, 0)) <= 0:
			return false
		left[it] -= 1
	return true


func _name(idx: int) -> String:
	for p: Dictionary in session.players.values():
		if int(p.index) == idx:
			return String(p.name)
	return ""


# ---------------------------------------------------------------- replication

func _publish() -> void:
	if session.is_host:
		keys = {}
		for p: Dictionary in session.players.values():
			keys[int(p.index)] = _key(int(p.index))
		if session.online:
			_rpc_offers.rpc(offers, keys)
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_offers(o: Dictionary, k: Dictionary) -> void:
	offers = o
	keys = k
	changed.emit()


## A textslmp line with the other player's name, in this player's language.
func _note(idx: int, key: String, who: String) -> void:
	if idx == session.my_index:
		_show_note(key, who)
		return
	var pid := session._pid_of(idx)
	if pid > 1 and session.online:
		_rpc_note.rpc_id(pid, key, who)


@rpc("authority", "call_remote", "reliable")
func _rpc_note(key: String, who: String) -> void:
	_show_note(key, who)


func _show_note(key: String, who: String) -> void:
	var fallback := {"lmp_trade_requested": "Player %s is offering you a swap",
		"lmp_trade_canceled": "Player %s refused to swap"}
	var t := NetStatus.lmp_text(key, who, String(fallback.get(key, key)))
	note.emit(t)
	session.message.emit(t)


func _note_text(idx: int, text: String) -> void:
	if idx == session.my_index:
		note.emit(text)
		session.message.emit(text)
		return
	var pid := session._pid_of(idx)
	if pid > 1 and session.online:
		_rpc_note_text.rpc_id(pid)


@rpc("authority", "call_remote", "reliable")
func _rpc_note_text() -> void:
	var t := RemakeText.t("The swap was cancelled.")
	note.emit(t)
	session.message.emit(t)
