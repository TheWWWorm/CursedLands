class_name NetSim
extends MultiplayerPeerExtension
## Remake test tool (not in the original): wraps the ENet peer and holds back
## what this side sends, to try co-op on a bad connection on one machine, and
## counts the bytes sent to each peer (bandwidth measurements).
##
## Tools pass --netsim=<latency_ms>,<jitter_ms>,<loss_pct> (also on the
## client): each packet this side sends waits latency/2 ± jitter/2 (so with
## both sides simulating, the round trip is about `latency` ± `jitter`). A
## "lost" packet: unreliable ones are dropped; reliable ones (ENet resends
## them) arrive one resend timeout later (latency + 200 ms) and hold back the
## packets behind them on the same channel, as ENet's ordering does.
## --netstat alone counts bytes without any delay.

var inner: ENetMultiplayerPeer
var latency := 0.0      # seconds, round trip
var jitter := 0.0
var loss := 0.0         # 0..1
## Bytes sent so far per target peer (0 = broadcast, counted per peer it reached).
var sent_bytes := {}
var sent_packets := 0
var lost_packets := 0

var _target := 0
var _mode := TRANSFER_MODE_RELIABLE
var _channel := 0
var _out: Array = []          # [time, target, channel, mode, bytes], sorted by time
var _last_at := {}            # "channel:reliable" -> time of the last packet queued
var _in: Array = []           # [peer, channel, mode, bytes]
var _peers := {}
var _rng := RandomNumberGenerator.new()


## The peer to use: `peer` itself unless the command line asks for the simulator.
static func wrap(peer: ENetMultiplayerPeer) -> MultiplayerPeer:
	var cfg := config()
	if cfg.is_empty():
		return peer
	var s := NetSim.new()
	s.inner = peer
	s.latency = float(cfg[0]) / 1000.0
	s.jitter = float(cfg[1]) / 1000.0
	s.loss = clampf(float(cfg[2]) / 100.0, 0.0, 1.0)
	s._rng.seed = hash(Time.get_ticks_usec())
	peer.peer_connected.connect(func(id):
		s._peers[id] = true
		s.peer_connected.emit(id))
	peer.peer_disconnected.connect(func(id):
		s._peers.erase(id)
		s.peer_disconnected.emit(id))
	print("netsim: latency %d ms, jitter %d ms, loss %.1f %%" % [cfg[0], cfg[1], cfg[2]])
	return s


## [latency_ms, jitter_ms, loss_pct] from --netsim= (--netstat = [0, 0, 0]); [] = off.
static func config() -> Array:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--netsim="):
			var p := a.trim_prefix("--netsim=").split(",")
			return [float(p[0]) if p.size() > 0 else 0.0, float(p[1]) if p.size() > 1 else 0.0,
				float(p[2]) if p.size() > 2 else 0.0]
		if a == "--netstat":
			return [0.0, 0.0, 0.0]
	return []


## The ENet peer behind a multiplayer peer (wrapped or not), or null.
static func enet_of(mp: MultiplayerAPI) -> ENetMultiplayerPeer:
	if mp == null or not mp.has_multiplayer_peer():
		return null
	var p := mp.multiplayer_peer
	if p is NetSim:
		return (p as NetSim).inner
	return p as ENetMultiplayerPeer


func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0


# ---------------------------------------------------------------- sending

func _put_packet_script(buffer: PackedByteArray) -> Error:
	var now := _now()
	var reliable := _mode == TRANSFER_MODE_RELIABLE
	var at := now + latency * 0.5 + _rng.randf_range(-0.5, 0.5) * jitter
	if loss > 0.0 and _rng.randf() < loss:
		lost_packets += 1
		if not reliable:
			return OK
		at += latency + 0.2
	if _mode != TRANSFER_MODE_UNRELIABLE:
		var key := "%d:%s" % [_channel, reliable]
		at = maxf(at, float(_last_at.get(key, 0.0)))
		_last_at[key] = at
	var item := [at, _target, _channel, _mode, buffer]
	var i := _out.size()
	while i > 0 and float(_out[i - 1][0]) > at:
		i -= 1
	_out.insert(i, item)
	return OK


func _flush_due() -> void:
	var now := _now()
	while not _out.is_empty() and float(_out[0][0]) <= now:
		var it: Array = _out.pop_front()
		var target := int(it[1])
		if target > 0 and (inner.get_peer(target) == null \
				or inner.get_peer(target).get_state() != ENetPacketPeer.STATE_CONNECTED):
			continue
		inner.set_target_peer(target)
		inner.transfer_channel = int(it[2])
		inner.transfer_mode = int(it[3])
		var buf: PackedByteArray = it[4]
		if inner.put_packet(buf) == OK:
			sent_packets += 1
			if target > 0:
				sent_bytes[target] = int(sent_bytes.get(target, 0)) + buf.size()
			else:
				for pid in _peer_ids():
					if target == 0 or int(pid) != -target:
						sent_bytes[pid] = int(sent_bytes.get(pid, 0)) + buf.size()


## Everything still held back goes out now (leaving the game).
func flush_now() -> void:
	for it: Array in _out:
		it[0] = 0.0
	_flush_due()


func _peer_ids() -> Array:
	return _peers.keys()


# ---------------------------------------------------------------- receiving

func _poll() -> void:
	_flush_due()
	inner.poll()
	while inner.get_available_packet_count() > 0:
		var peer := inner.get_packet_peer()
		var ch := inner.get_packet_channel()
		var mode := inner.get_packet_mode()
		_in.append([peer, ch, mode, inner.get_packet()])


func _get_available_packet_count() -> int:
	return _in.size()


func _get_packet_script() -> PackedByteArray:
	return _in.pop_front()[3] if not _in.is_empty() else PackedByteArray()


func _get_packet_peer() -> int:
	return int(_in[0][0]) if not _in.is_empty() else 0


func _get_packet_channel() -> int:
	return int(_in[0][1]) if not _in.is_empty() else 0


func _get_packet_mode() -> TransferMode:
	return int(_in[0][2]) if not _in.is_empty() else TRANSFER_MODE_RELIABLE


func _get_max_packet_size() -> int:
	return 1 << 24


# ---------------------------------------------------------------- the rest goes to ENet

func _set_transfer_channel(ch: int) -> void:
	_channel = ch


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(mode: TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> TransferMode:
	return _mode


func _set_target_peer(peer: int) -> void:
	_target = peer


func _get_unique_id() -> int:
	return inner.get_unique_id()


func _is_server() -> bool:
	return inner.get_unique_id() == 1


func _is_server_relay_supported() -> bool:
	return inner.is_server_relay_supported()


func _get_connection_status() -> ConnectionStatus:
	return inner.get_connection_status()


func _set_refuse_new_connections(enable: bool) -> void:
	inner.refuse_new_connections = enable


func _is_refusing_new_connections() -> bool:
	return inner.refuse_new_connections


func _disconnect_peer(peer: int, force: bool) -> void:
	inner.disconnect_peer(peer, force)


func _close() -> void:
	_out.clear()
	_in.clear()
	inner.close()
