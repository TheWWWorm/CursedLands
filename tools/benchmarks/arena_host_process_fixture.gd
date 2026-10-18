extends Node
## Test-only army setup around the production local-authority handshake and
## lifecycle. No fixture commands are accepted by the game's network protocol.
class DiagnosticAuthority extends ArenaOnlineSession:
	func _peer_disconnected(id: int) -> void:
		print("AUTHORITY_DISCONNECT_DIAGNOSTIC ",Time.get_ticks_msec()," id=",id," member=",members.get(id,{}))
		super._peer_disconnected(id)
var host: ArenaOnlineSession
var base := ""
func frames(count: int) -> void:
	for i in count: await get_tree().process_frame
func _ready() -> void: run.call_deferred()
func wait_file(suffix: String) -> bool:
	var deadline := Time.get_ticks_msec() + 120000
	while not FileAccess.file_exists(base + suffix) and Time.get_ticks_msec() < deadline:
		await frames(1)
	return FileAccess.file_exists(base + suffix)
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena-stress-config="): base = arg.trim_prefix("--arena-stress-config=")
	host = DiagnosticAuthority.new(); add_child(host)
	var config := host.local_host.configure(base)
	if config.is_empty(): get_tree().quit(1); return
	GameData._window_gen += 1
	var error := host.host(int(config.port), bool(config.websocket))
	host.local_host.listening(error)
	if error != OK: get_tree().quit(1); return
	while host.game == null: await frames(1)
	print("HOST_PROCESS_FILL_BEGIN ",Time.get_ticks_msec())
	host.game.set_process(false); host.game.run.wave = 21
	for player in 9:
		var company := host.game.run.company(player)
		company.army.clear(); company.wave = 21; company.training = 126
		company.gold = 50; company.auto_save = false
		for family in [7,9,10,11,17,18,22,23,8]: company._recruit(family, 2, 10)
		company.arrange()
	host.game.run._prepare_round()
	for plan: Dictionary in host.game.run.bot_plans: plan.done = true
	host.game._prepare()
	print("HOST_PROCESS_FILL_END ",Time.get_ticks_msec())
	FileAccess.open(base + ".prepared", FileAccess.WRITE).store_string("ready")
	if not await wait_file(".round"): await host.local_host.shutdown(); return
	host.game.battle_speed = int(FileAccess.get_file_as_string(base + ".round"))
	host.game.start_round()
	FileAccess.open(base + ".battle", FileAccess.WRITE).store_string("ready")
	if not await wait_file(".run"): await host.local_host.shutdown(); return
	host.game.set_process(true)
	var start := Time.get_ticks_usec(); var next := start
	var census := []
	while host.game != null and Time.get_ticks_usec() - start < 90000000:
		await frames(1)
		if host.game == null: break
		if Time.get_ticks_usec() < next: continue
		var alive := []; var clocks := []
		for player in 9:
			var battle := host.game.encounter(player)
			alive.append(battle.world.unit_rows().filter(func(u): return not u.dead).size())
			clocks.append(battle.world.time)
		var row := {"wall":(Time.get_ticks_usec()-start)/1000000.0,"stage":host.game.run.stage,"sim":clocks,"alive":alive}
		census.append(row)
		FileAccess.open(base + ".census.tmp", FileAccess.WRITE).store_string(JSON.stringify(row))
		DirAccess.rename_absolute(base + ".census.tmp", base + ".census")
		next = Time.get_ticks_usec() + 1000000
	FileAccess.open(base + ".worker.json", FileAccess.WRITE).store_string(JSON.stringify(census,"\t"))
	if host.game != null: await host.local_host.shutdown()
