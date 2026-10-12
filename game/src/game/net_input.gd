class_name NetInput
extends RefCounted
## Small redundant UDP copies bypass ENet's reliable resend backoff. The
## reliable copy remains mandatory, including for large inventory commands.
## Every copy shares one sequence; the authority consumes each order once.
const WINDOW := 128
const PACKET_BYTES := 1000
const COMMAND_BYTES := 900
const RETRY_MS := 100

var serial := 0
var pending := {}
var last := 0
var waiting := {}


func prepare(cmd: Dictionary) -> Dictionary:
	serial += 1
	cmd = cmd.duplicate(true)
	cmd._input_seq = serial
	if pending.size() < WINDOW and var_to_bytes(cmd).size() <= COMMAND_BYTES:
		pending[serial] = cmd
	return cmd


func acknowledge(seq: int) -> void:
	if seq <= 0 or seq > serial: return
	for key: int in pending.keys():
		if key <= seq: pending.erase(key)


func packet() -> PackedByteArray:
	var commands := []
	var bytes := PackedByteArray()
	for cmd: Dictionary in pending.values():
		commands.append(cmd)
		var candidate := var_to_bytes(commands)
		if candidate.size() > PACKET_BYTES: break
		bytes = candidate
	return bytes


func receive(cmd: Dictionary) -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	if typeof(cmd.get("_input_seq")) != TYPE_INT: return ready
	var seq: int = cmd._input_seq
	if seq <= last or seq - last > WINDOW: return ready
	if not waiting.has(seq): waiting[seq] = cmd
	while waiting.has(last + 1):
		last += 1
		ready.append(waiting[last])
		waiting.erase(last)
	return ready
