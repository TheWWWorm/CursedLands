extends Node
## Use an isolated user profile. Physical slow-load regression complements
## these exact process-liveness and fallback-watchdog boundaries.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func _ready() -> void:
	var s:=Session.new();add_child(s)
	var host:=s.local_host
	host.parent_id=OS.get_process_id()
	host._owner_seen=Time.get_ticks_msec()-120001
	check(not host._owner_gone(),"a live local owner survives stale frame heartbeats")
	host.parent_id=2147483647
	check(host._owner_gone(),"an exited owner still shuts its worker down")
	host.parent_id=-1
	check(host._owner_gone(),"missing process identity retains heartbeat watchdog")
	host._owner_seen=Time.get_ticks_msec()
	check(not host._owner_gone(),"fresh fallback heartbeat remains alive")
	s.free()
	print("LOCAL_HOST_LIVENESS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
