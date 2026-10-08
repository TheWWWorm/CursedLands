extends Node
## Actual saved progress and deferred thumbnails, using isolated save slots.
var checks := 0
var failures := 0
var session: Session
var background: ColorRect
var hero: Dictionary
var zones: Array[String] = ["gz1g", "gz2g", "gz3g", "gz4g"]

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func settle() -> void:
	for i in 12: await get_tree().process_frame
	await RenderingServer.frame_post_draw

func send(zone: String, money: int) -> void:
	session.coop._rpc_package({"campaign_id":GameData.campaign_id, "host":"Preview host",
		"hero":hero, "purse":{"money":money, "items":["rune:e1"]},
		"move":{"zone":zone, "day":2, "world_time":8.0}})

func picture(slot: String) -> String:
	return FileAccess.get_sha256(SaveInfo.path(slot, "shot.png"))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"net_upnp":0, "net_lan":0, "net_directory":0}, true)
	if GameData.campaign_id == CampaignProfile.ASTRAL: zones = ["gz1h", "gz2h", "gz3h", "gz4h"]
	background = ColorRect.new()
	background.color = Color.RED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var original := CoopProgress.fresh_state()
	original.current_zone = zones[0]
	original.money = 17
	hero = CoopProgress.main_hero(original).duplicate(true)
	original.save(SaveInfo.path("preview_origin"))
	session = Session.new()
	add_child(session)
	session.set_physics_process(false)
	session.is_host = false
	session.zone_id = zones[0]
	session.coop._origin_slot = "preview_origin"
	await settle()
	send(zones[0], 100)
	await settle()
	var slot := session.coop.last_merged
	var first := picture(slot)
	check(not first.is_empty(), "first progress update has a thumbnail")
	var img := Image.load_from_file(SaveInfo.path(slot, "shot.png"))
	check(img != null and img.get_size() == SaveInfo.SHOT_SIZE, "thumbnail retains native preview size")
	check(CampaignState.load_from(SaveInfo.path(slot)).money == 100, "first progress is saved")
	background.color = Color.GREEN
	send(zones[0], 200)
	send(zones[0], 300)
	await settle()
	check(picture(slot) == first, "same-location progress leaves its thumbnail unchanged")
	var saved := CampaignState.load_from(SaveInfo.path(slot))
	check(saved.money == 300 and saved.items == ["rune:e1"] and session.coop.merged_count == 3,
		"every coalesced preview still saves current progress and acknowledgement")
	check(CampaignState.load_from(SaveInfo.path("preview_origin")).money == 17, "brought save stays intact")
	# A destination package can precede the client's loading completion.
	send(zones[1], 400)
	await settle()
	check(picture(slot) == first, "different host location is not photographed for this save")
	session.zone_id = zones[1]
	background.color = Color.BLUE
	send(zones[1], 500)
	await settle()
	var second := picture(slot)
	check(not second.is_empty() and second != first, "arrival in a new saved location refreshes its thumbnail")
	# Cancel a deferred request by leaving before the capture runs.
	session.zone_id = zones[2]
	background.color = Color.YELLOW
	send(zones[2], 600)
	session.zone_id = zones[3]
	await settle()
	check(picture(slot) == second, "leaving cancels a deferred wrong-location capture")
	session.zone_id = zones[2]
	background.color = Color.MAGENTA
	send(zones[2], 700)
	await settle()
	var third := picture(slot)
	check(not third.is_empty() and third != second, "cancelled preview retries after arrival")
	saved = CampaignState.load_from(SaveInfo.path(slot))
	check(saved.money == 700 and saved.current_zone == zones[2], "capture cancellation does not cancel saved progress")
	session.zone_id = zones[3]
	session.loading_game = true
	background.color = Color.WHITE
	send(zones[3], 750)
	await settle()
	check(picture(slot) == third, "loading world is not used as a progress preview")
	session.loading_game = false
	background.color = Color.BLACK
	send(zones[3], 760)
	await settle()
	var before_loading := third
	third = picture(slot)
	check(not third.is_empty() and third != before_loading, "loading capture retries after the world is ready")
	session.zone_id = zones[0]
	background.color = Color.CYAN
	send(zones[0], 800)
	session.queue_free()
	await settle()
	check(picture(slot) == third, "closing the session cancels its pending preview")
	SaveInfo.write_shot("ordinary_preview", get_viewport())
	await settle()
	check(not picture("ordinary_preview").is_empty(), "ordinary save capture still works without a guard")
	print("COOP_PROGRESS_PREVIEW ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
