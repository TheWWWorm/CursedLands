extends Node
## Local screen-coordinate diagnostics, real-time sampling and discoverability.
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func samples() -> int:
	var n:=0
	for line:String in DeveloperConsole.lines:
		if "x=" in line and "y=" in line:n+=1
	return n
func wait(seconds:float):
	var end:=Time.get_ticks_usec()+roundi(seconds*1000000.0)
	while Time.get_ticks_usec()<end:await get_tree().process_frame
func _ready():
	var c:=DeveloperConsole
	c.visible=false;c.unlocked=false;c.lines.clear()
	c.run("cursor")
	check(samples()==1 and not c.unlocked and c._session==null,"one-shot cursor works locally before unlock without a campaign")
	check(ConsoleCatalog.candidates("cur",3).any(func(row):return row.text=="cursor"),"cursor command appears in root completion")
	c.run("cursor on")
	var before:=samples()
	await wait(0.26)
	check(samples()>=before+2,"default interval repeatedly samples a stationary cursor")
	c._close();before=samples()
	await wait(0.16)
	check(samples()>before and not c.visible,"sampling continues while the console is closed")
	c.visible=true
	check(c.output.get_parsed_text().contains(c.lines[-1]),"reopening displays samples collected while hidden")
	c.run("cursor off");before=samples()
	await wait(0.15)
	check(samples()==before and not c.is_processing(),"off stops further samples and disables polling")
	for invalid:String in ["cursor on 0","cursor on -1","cursor on 0.001","cursor on 11","cursor on 1e100","cursor on nan","cursor off 1","cursor nope","cursor on 0.1 extra"]:
		c.run(invalid)
		check(c._cursor_interval==0.0 and samples()==before,"invalid interval/action leaves logging stopped: "+invalid)
	c.run("cursor on 0.05");before=samples()
	Engine.time_scale=0.1;get_tree().paused=true
	await wait(0.18)
	get_tree().paused=false;Engine.time_scale=1.0
	check(samples()>=before+2,"sampling uses real time during pause and slow campaign speed")
	c.run("cursor off")
	if DisplayServer.get_name()!="headless":
		get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1280,800)
		get_window().position=Vector2i.ZERO;get_window().grab_focus()
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		for point in [Vector2(123,234),Vector2(456,345)]:
			Input.warp_mouse(point)
			for i in 3:await get_tree().process_frame
			c.run("cursor")
			check(c.lines[-1].contains("x=%.1f"%point.x) and c.lines[-1].contains("y=%.1f"%point.y),"real pointer coordinates use the game viewport: "+str(point))
	c.run("log cursor-test.txt")
	var saved:=FileAccess.get_file_as_string("user://console/cursor-test.txt")
	check(saved.contains("x=") and saved.contains("y="),"cursor samples are available in ordinary console exports")
	var capacity:=c.line_limit;c.line_limit=20
	for i in 25:c.run("cursor")
	check(c.lines.size()==20,"continuous diagnostics respect retained-output capacity")
	c.line_limit=capacity
	for language:String in ["en","ru","de"]:
		RemakeText.lang=language;c.lines.clear();c.visible=true;c._refresh_labels()
		c.run("help cursor")
		var help:=ConsoleCatalog.help_rows("cursor")[0]
		check(language=="en" or help.description!=ConsoleCatalog.ROWS.filter(func(row):return String(row[0]).begins_with("cursor "))[0][1],"cursor help is localized: "+language)
		c.run("cursor on 0.1");await wait(0.12);c.run("cursor off")
		check(c.lines[-1]==RemakeText.t("Cursor logging stopped."),"stop status is localized: "+language)
		c.input.grab_focus();c._set_input("cursor o")
		await get_tree().process_frame;c._complete(true)
		check(c._candidates.size()==2 and c._cursor_interval==0.0,"on/off completion never starts logging: "+language)
		c.run("console f")
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://console-cursor-"+language+".png")
			print("CAPTURE console-cursor-",language)
	if DisplayServer.get_name()!="headless":
		get_window().size=Vector2i(640,480)
		for i in 6:await get_tree().process_frame
		check(Rect2(Vector2.ZERO,Vector2(640,480)).grow(1).encloses(c.panel.get_global_rect()),"German cursor console fits a narrow viewport")
	c._close();RemakeText.lang="en"
	print("CONSOLE_CURSOR ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
