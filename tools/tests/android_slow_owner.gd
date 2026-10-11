extends Node
## Reproduce a cold/slow renderer while retaining the production ENet pump.
var s: Session
var held := false
var checks := 0
var failures := 0
var rows: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	rows.append({"ok":ok,"label":label})
	print("PASS " if ok else "FAIL ",label)

func presented(frame: int) -> void:
	if held or frame!=8 or s==null or not s.local_host.frontend: return
	held=true
	print("SLOW_OWNER_BEGIN keeping ENet alive for 125 seconds")
	var start:=Time.get_ticks_msec()
	var last:=0
	while Time.get_ticks_msec()-start<125000:
		NetStatus.keep_alive()
		OS.delay_msec(50)
		var elapsed:=(Time.get_ticks_msec()-start)/1000
		if elapsed>=last+20:
			last=elapsed;print("SLOW_OWNER elapsed=",elapsed)
	print("SLOW_OWNER_END worker_alive=",s.local_host._process_alive())

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":1},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	s=Session.new();get_parent().add_child(s)
	var g:=Game.new();g.session=s;s.game=g;get_parent().add_child(g)
	LoadingScreen.on_presented=presented
	await s.new_campaign(false)
	var deadline:=Time.get_ticks_msec()+150000
	while (s.world==null or s.loading_game or s._remote_loading) and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	LoadingScreen.on_presented=Callable()
	check(held,"actual client loading frame exercised slow renderer")
	check(s.world!=null,"client finishes loading its visible world")
	check(s.local_host._process_alive(),"local authority survives slow loading with a live owner")
	var before:=s.world.time if s.world else 0.0
	deadline=Time.get_ticks_msec()+4000
	while s.world and s.world.time<=before and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	check(s.world!=null and s.world.time>before,"world runs after slow loading")
	var answer:=await s.local_host.request("save",{"slot":"android_report_probe","camera":s.local_host.view()})
	check(answer.get("ok",false),"saving still works after slow loading")
	await s.local_host.stop()
	var f:=FileAccess.open("user://slow-load.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"  "));f.close()
	print("SLOW_LOAD_REPORT ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
