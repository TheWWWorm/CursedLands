extends Node
## Developer-only entry point. Every program receives a fresh process/profile.

func _ready() -> void:
	var script_path := ""
	var test_seed := 20261020
	var campaign := ""
	var display := "headless"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--suite-script="): script_path = arg.trim_prefix("--suite-script=")
		if arg.begins_with("--suite-seed="): test_seed = int(arg.trim_prefix("--suite-seed="))
		if arg.begins_with("--suite-campaign="): campaign = arg.trim_prefix("--suite-campaign=")
		if arg.begins_with("--suite-display="): display = arg.trim_prefix("--suite-display=")
	var actual_display := "headless" if DisplayServer.get_name() == "headless" else "rendered"
	if actual_display != display:
		push_error("Gameplay test display does not match the selected mode")
		get_tree().quit(2)
		return
	var profile := {}
	for key in ["confine_mouse", "show_fps", "volume_sfx", "volume_stream", "volume_voice"]:
		profile[key] = GameData.option(key)
	if profile != {"confine_mouse":0, "show_fps":1, "volume_sfx":0, "volume_stream":0, "volume_voice":0}:
		push_error("Gameplay suite requires an isolated, muted development profile")
		get_tree().quit(2)
		return
	if GameData.campaign_id != campaign:
		push_error("Gameplay test was given the wrong campaign data")
		get_tree().quit(2)
		return
	if not script_path.begins_with("res://tools/tests/") or not script_path.ends_with(".gd"):
		push_error("Invalid gameplay test path")
		get_tree().quit(2)
		return
	seed(test_seed)
	Engine.max_fps = 60
	GameData.options.merge({"auto_graphics":0, "autosave":0, "show_tutorial":0,
		"net_upnp":0, "net_lan":0, "net_directory":0, "net_websocket":0}, true)
	print("GAMEPLAY_SUITE_START ", JSON.stringify({
		"script":script_path, "seed":test_seed, "profile":profile, "campaign":GameData.campaign_id,
		"engine":Engine.get_version_info(), "user_dir":OS.get_user_data_dir(),
		"display":actual_display, "display_driver":DisplayServer.get_name(),
		"rendering_method":RenderingServer.get_current_rendering_method()}))
	var script: Script = load(script_path)
	if script == null or not script.can_instantiate():
		push_error("Gameplay test could not be instantiated")
		get_tree().quit(2)
		return
	var test: Node = script.new()
	# Preserve the normal --tool sibling layout. LocalHost RPC paths must
	# still be /root/Main/Session on both the frontend and worker.
	get_parent().add_child.call_deferred(test)
