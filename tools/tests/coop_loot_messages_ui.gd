extends "arena_expansion_ui.gd"
## Inspect the actual original message window with localized pickup/copy text.
func _ready() -> void:
	OS.add_logger(errors);await frames(8)
	get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1280,800)
	var language:=RemakeText.lang
	var background:=ColorRect.new();background.color=Color("334554")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var log:=MessageLog.new();add_child(log);await frames(8)
	var thin:="material.thin"
	var items:=[thin,thin,thin,thin,thin,thin,thin,thin]
	var descriptions:=Items.log_stacks(items)
	var copy:=CoopProgress.copy_text({"who":"Worm","items":items,"money":0})
	check(descriptions.size()==1 and "x8" in descriptions[0],"eight thin-leather units form one description")
	check(copy.count(Items.log_name(thin))==1 and copy.contains(descriptions[0]),"shared notice retains the finder's localized description")
	log.messages.add_text(GameData.text("string combat_picked_up").strip_edges()+" "+descriptions[0]+"\n")
	log.messages.add_text(copy+"\n")
	await frames(8)
	check(not log.messages.get_parsed_text().contains("material.thin"),"original localized material name replaces internal ID")
	check(log.messages.get_content_height()<=MessageLog.TEXT.size.y*log._k()+1,"both localized notices fit the original text window: "+language)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://shared-loot-"+language+".png")
	print("CAPTURE shared-loot-",language)
	log.queue_free();background.queue_free();await frames(4)
	check(errors.messages.is_empty(),"message window has no script/render errors: "+str(errors.messages))
	print("COOP_LOOT_MESSAGES_UI ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
