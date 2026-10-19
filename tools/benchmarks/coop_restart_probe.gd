extends "./session_retention.gd"
## Continue a real deep-combat save, then save the settled endpoint before
## either peer disconnects. Reload retention-end with --stationary for a
## matched restart comparison. Normal movement, combat and damage stay live.
var settled := false

func run() -> void:
	route = [Vector2(180,300),Vector2(160,240),Vector2(130,200),Vector2(180,160),Vector2(220,220)]
	await super.run()

func decide(t: float) -> void:
	if t >= duration - 60.0:
		if not settled:
			var h := hero()
			if h: g.issue({"t":"stop", "units":[h.uid]})
			settled = true
		stage = "settled"
		return
	super.decide(t)

func finish() -> void:
	if guest:
		# Keep this party in the authority's final save until the owner has
		# received the save acknowledgement and stopped the local server.
		await until(func():return not s.online or s.multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED, 20.0)
	elif not stationary:
		var answer: Dictionary = await s.local_host.request("save", {"slot":"retention-end", "name":"", "camera":s.local_host.view(), "image":PackedByteArray()})
		print("RESTART_ENDPOINT_SAVE ", JSON.stringify(answer))
		if not bool(answer.get("ok",false)):
			push_error("Could not save the measured endpoint")
			get_tree().quit(2)
			return
	await super.finish()
