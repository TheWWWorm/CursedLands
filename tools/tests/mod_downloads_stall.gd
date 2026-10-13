extends Node
## Regression for a TLS server that accepts a request but sends no headers.
## Use private XDG directories, --mod-tests, --stall-port and --stall-cert.
var checks := 0
var failures := 0

class TLSDownload extends ModDownload:
	var certificate: X509Certificate
	func _request(url: String) -> void:
		_http.set_tls_options(TLSOptions.client(certificate))
		super._request(url)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--mod-tests"): get_tree().quit(2); return
	var port := 0
	var cert_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stall-port="): port = arg.trim_prefix("--stall-port=").to_int()
		if arg.begins_with("--stall-cert="): cert_path = arg.trim_prefix("--stall-cert=")
	var certificate := X509Certificate.new()
	check(port > 0 and certificate.load(cert_path) == OK, "local TLS fixture configured")
	if failures: get_tree().quit(1); return
	for mode in ["cancel", "timeout", "destroy"]:
		var d := TLSDownload.new()
		d.certificate = certificate
		add_child(d)
		d.item = {"url": "https://127.0.0.1:%d/stall" % port, "hosts": [], "bytes": 1024}
		d._work = "user://mods/.download-stall-" + mode
		DirAccess.make_dir_recursive_absolute(d._work)
		d.busy = true
		# The local test port bypasses catalog selection, never production URL checks.
		d._start_source(d.item)
		var deadline := Time.get_ticks_msec() + 10000
		while d.busy and d._http.get_http_client_status() != HTTPClient.STATUS_REQUESTING and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		check(d.busy and d._http.get_http_client_status() == HTTPClient.STATUS_REQUESTING, "waiting for response headers: " + mode)
		for i in 5: await get_tree().process_frame
		var pending := d._work
		var began := Time.get_ticks_msec()
		if mode == "cancel":
			d.cancel()
			check(not d.busy and d.status == "Download cancelled.", "cancel stalled TLS request")
		elif mode == "timeout":
			d._last_bytes = d._http.get_downloaded_bytes()
			d._last_progress = Time.get_ticks_msec() - ModDownload.IDLE_TIMEOUT - 1
			d._process(0.0)
			check(not d.busy and d.status.contains("stalled"), "idle timeout closes stalled TLS request")
		else:
			d.free()
		check(Time.get_ticks_msec() - began < 1000, "stalled request cleanup stays responsive: " + mode)
		check(not DirAccess.dir_exists_absolute(pending), "stalled request staging removed: " + mode)
		if is_instance_valid(d): d.free()
	print("MOD_DOWNLOADS_STALL ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(1 if failures else 0)
