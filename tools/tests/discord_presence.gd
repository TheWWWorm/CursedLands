extends Node
func _ready()->void:
	var p:=get_node("/root/DiscordPresence")
	if p.transport==null:printerr("FAIL native Discord IPC missing");get_tree().quit(1);return
	for text:String in ["Suslanger", "Суслангер — кооператив ".repeat(20), "Überleben ".repeat(20)]:
		var limited:String=p.activity_text(text)
		if not text.begins_with(limited) or limited.to_utf8_buffer().size()>128:
			printerr("FAIL localized activity truncation");get_tree().quit(1);return
	print("PASS activity preserves whole localized characters within the UTF-8 limit")
	GameData.options.discord_presence=1
	if p.application_id != "1561645781533069393":
		printerr("FAIL bundled public application ID");get_tree().quit(1);return
	p.active=true;p.test_mode=true
	p.desired={"details":"Campaign","state":"Suslanger","timestamps":{"start":12345678}}
	var deadline:=Time.get_ticks_msec()+15000
	while p.sent.is_empty() and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	if p.sent.is_empty():printerr("FAIL handshake/activity");get_tree().quit(1);return
	for i in 30:await get_tree().process_frame
	GameData.options.discord_presence=0
	await get_tree().process_frame
	print("PASS disabling clears and disconnects: ",not p.transport.is_open())
	get_tree().quit(0 if not p.transport.is_open() else 1)
