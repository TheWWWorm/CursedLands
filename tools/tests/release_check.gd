extends Node
## Deterministic API/policy checks, including a real HTTPRequest over loopback.
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", message)

func release(tag := "v9.0.0") -> Dictionary:
	return {"tag_name": tag, "draft": false, "prerelease": false, "html_url": "https://untrusted.invalid/ignored"}

func response(c: ReleaseCheck, data: Variant, code := 200, headers := PackedStringArray()) -> void:
	c._last_ok = false
	c._completed(HTTPRequest.RESULT_SUCCESS, code, headers, JSON.stringify(data).to_utf8_buffer())

func _ready() -> void:
	for pair in [["1.10.0", "1.9.9"], ["2.0.0", "1.99.99"], ["v1.2.4", "1.2.3"],
		["1.2.3", "1.2.3-preview.1"], ["1.2.3+new", "1.2.3-beta+old"], ["999999999999999999999.0.0", "99999999999999999999.0.0"]]:
		check(ReleaseCheck.newer_stable(pair[0], pair[1]), "newer stable: " + str(pair))
	for pair in [["1.9.9", "1.10.0"], ["1.2.3", "1.2.3"], ["1.2.3+new", "1.2.3+old"],
		["1.3.0-preview.1", "1.2.3"], ["v01.2.3", "1.0.0"], ["1.2.3", "unknown"]]:
		check(not ReleaseCheck.newer_stable(pair[0], pair[1]), "no false upgrade: " + str(pair))
	for invalid in ["", "v1.2", "1.2.3.4", "01.2.3", "1.02.3", "1.2.03", "1.2.3-01", "1.2.3/evil", "1.2.3\n", "1.2.3+", "1.2.3-", "1.2.3-.."]:
		check(ReleaseCheck.version_parts(invalid).is_empty(), "reject malformed version: " + invalid)
	var c := ReleaseCheck.new()
	c.cache_path = "user://release-check-test.cfg"
	add_child(c)
	c.automatic()
	check(c._request == null, "tools never make implicit network requests")
	response(c, release())
	check(c.state == ReleaseCheck.State.AVAILABLE, "new stable offers an update")
	check(c.release_url() == ReleaseCheck.RELEASES + "/tag/v9.0.0", "release target is derived from our trusted repository")
	var restored := ReleaseCheck.new()
	restored.cache_path = c.cache_path
	add_child(restored)
	restored.load_cache()
	check(restored.state == ReleaseCheck.State.AVAILABLE, "verified release survives returning to the menu")
	for invalid in [null, [], {}, {"message":"rate limited"}, {"tag_name":42,"draft":false,"prerelease":false}, {"tag_name":"v9.0.0","draft":0,"prerelease":0}, release("1.3.0-preview.1"), release("v01.0.0")]:
		c.latest_tag = ""
		response(c, invalid)
		check(c.state == ReleaseCheck.State.FAILED, "invalid metadata does not offer an update")
	for flag in ["draft", "prerelease"]:
		var data := release()
		data[flag] = true
		response(c, data)
		check(c.state == ReleaseCheck.State.FAILED, "ignore " + flag)
	response(c, release("v" + c.installed_version()))
	check(c.state == ReleaseCheck.State.CURRENT, "equal version is current")
	response(c, release("v1.0.5"))
	check(c.state == ReleaseCheck.State.CURRENT, "never downgrade a newer local build")
	c.latest_tag = ""
	c._last_ok = false
	c._completed(HTTPRequest.RESULT_TIMEOUT, 0, [], [])
	check(c.state == ReleaseCheck.State.FAILED, "offline/timeout has a recoverable state")
	c._completed(HTTPRequest.RESULT_SUCCESS, 200, [], "{bad json".to_utf8_buffer())
	check(c.state == ReleaseCheck.State.FAILED, "malformed JSON fails quietly")
	response(c, release())
	c._last_ok = false
	c._completed(HTTPRequest.RESULT_CANT_RESOLVE, 0, [], [])
	check(c.state == ReleaseCheck.State.AVAILABLE, "offline check retains a verified update offer")
	var now := int(Time.get_unix_time_from_system())
	c.latest_tag = ""
	response(c, {}, 429, PackedStringArray(["Retry-After: 1800", "X-RateLimit-Reset: " + str(now + 3600)]))
	check(c._retry_at >= now + 3600 and not c.due(true, now + 1000), "manual and automatic checks honor rate-limit headers")
	c._retry_at = 0
	c._last_attempt = now
	c._last_ok = true
	check(not c.due(false, now + 86399) and c.due(false, now + 86400), "successful auto-checks wait one day")
	check(not c.due(true, now + 59) and c.due(true, now + 60), "manual retries are bounded")
	c._last_ok = false
	check(not c.due(false, now + 899) and c.due(false, now + 900), "failed auto-checks back off")
	c.state = ReleaseCheck.State.CHECKING
	check(not c.due(true, now + 90000), "duplicate requests cannot overlap")
	c.state = ReleaseCheck.State.IDLE
	var server := TCPServer.new()
	check(server.listen(0, "127.0.0.1") == OK, "open isolated HTTP fixture")
	c._endpoint = "http://127.0.0.1:%d/latest" % server.get_local_port()
	c._last_attempt = 0
	c.check_now()
	check(c.state == ReleaseCheck.State.CHECKING and c._request != null, "check returns immediately while request runs")
	check(c._request.timeout == 8.0 and c._request.body_size_limit == ReleaseCheck.BODY_LIMIT and c._request.max_redirects == 0, "transport bounds time, body and redirects")
	var peer: StreamPeerTCP
	var request := ""
	var sent := false
	var frames := 0
	var deadline := Time.get_ticks_msec() + 5000
	while c.state == ReleaseCheck.State.CHECKING and Time.get_ticks_msec() < deadline:
		frames += 1
		if peer == null and server.is_connection_available(): peer = server.take_connection()
		if peer:
			peer.poll()
			if peer.get_available_bytes() > 0: request += peer.get_utf8_string(peer.get_available_bytes())
			if not sent and "\r\n\r\n" in request:
				var body := JSON.stringify(release())
				peer.put_data(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [body.to_utf8_buffer().size(), body]).to_utf8_buffer())
				sent = true
		await get_tree().process_frame
	check(sent and c.state == ReleaseCheck.State.AVAILABLE, "real HTTP transport parses a published release")
	check(request.begins_with("GET /latest HTTP/1.1") and "application/vnd.github+json" in request, "request is a read-only public JSON GET")
	check(frames > 1, "game frames advance during the request")
	# Exercise the production timeout against a server that never answers.
	c._last_attempt = 0
	c.latest_tag = ""
	c.check_now()
	deadline = Time.get_ticks_msec() + 10000
	while c.state == ReleaseCheck.State.CHECKING and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(c.state == ReleaseCheck.State.FAILED and c._request == null, "HTTP timeout recovers and releases the request")
	server.stop()
	if peer: peer.disconnect_from_host()
	if OS.get_cmdline_user_args().has("--release-check-live"):
		c._endpoint = ReleaseCheck.API
		c._last_attempt = 0
		c.check_now()
		deadline = Time.get_ticks_msec() + 10000
		while c.state == ReleaseCheck.State.CHECKING and Time.get_ticks_msec() < deadline: await get_tree().process_frame
		check(c._last_ok, "live GitHub public endpoint accepts the production request")
		print("RELEASE_CHECK_LIVE ", c.latest_tag)
	c.free()
	restored.free()
	print("RELEASE_CHECK ", checks, " checks ", failures, " failures")
	TexUpscale.shutdown()
	get_tree().quit(1 if failures else 0)
