class_name CrashReport
extends Node
## Remake: crash diagnosis. Godot writes every print and error to
## user://logs/godot.log (debug/file_logging, on for every platform but the
## web; the previous runs' logs are kept as godot_<date>.log, rotated at each
## start), GameData.trace adds a line at each lifecycle step (zone load, save,
## options), so the last lines tell where a run stopped.
## A running session keeps a marker, user://crash/running_<pid>.cfg, with its
## session info (version, system, GPU, renderer, graphics tier and options, the
## current zone, the last trace line, foreground / background). A clean quit
## removes it (_exit_tree, the window's close request); a marker left at the
## next start means that session ended unexpectedly, and the main menu shows a
## box (CrashReportBox) to save or copy a report. Android / iOS: a session
## killed while paused (in the background) is the system's doing, not a crash,
## and is only noted in the log; so is one that had lost the focus (the
## recent-apps screen: a swipe there can close the app before Android pauses
## it, the marker then still says foreground). Markers of another instance still running (two
## game windows on one PC) are left alone.
## Reports go where the player can reach them: Android → the shared Download
## folder (no permission needed for files the app creates there on Android 10+;
## Godot writes through MediaStore), else the app's own external folder
## Android/data/<package>/files/Documents; desktop → Downloads, else Documents;
## always user://reports as the last resort; web → a browser download.

const DIR := "user://crash"
const LOG_DIR := "user://logs"
const LOG_FILE := "user://logs/godot.log"
const CLIP_LINES := 200    # clipboard: the log's last lines
const FILE_LINES := 5000   # saved report: the log's last lines per log
const MARK_PREFIX := "running_"

static var instance: CrashReport
## Tests: where reports are saved instead of the player's folders.
static var save_dir_override := ""
## Off on the web: a closed tab never quits cleanly, and there is no log file.
static var enabled := not OS.has_feature("web")
## Android / iOS: a marker left without the focus is a close from the
## recent-apps screen, not a crash (scan). Tests set it on a PC.
static var handheld := Portability.handheld()

## The info of the previous session that ended unexpectedly ({} = none), with
## "log" = its log file. CrashReportBox offers it once.
var previous := {}
var info := {}
var _marker := ""
var _done := false


func _ready() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "CrashReport"
	if not enabled:
		return
	var sid := "%08x%04x" % [randi(), Time.get_ticks_usec() & 0xffff]
	info = {"session": sid, "pid": OS.get_process_id(), "started": Time.get_datetime_string_from_system(false, true),
		"state": "foreground", "focus": "in", "zone": "(menu)", "last": ""}
	_collect()
	GameData.trace("session %s: %s, %s, %s, %s" % [sid, info.version, info.os, info.gpu, info.renderer])
	previous = scan(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(DIR)
	_marker = DIR.path_join("%s%d.cfg" % [MARK_PREFIX, OS.get_process_id()])
	_write()


## Version, system, GPU, renderer, graphics tier and options.
func _collect() -> void:
	info.version = String(ProjectSettings.get_setting("application/config/version", "?"))
	info.engine = String(Engine.get_version_info().get("string", ""))
	info.os = "%s %s" % [OS.get_name(), OS.get_version()]
	if OS.get_distribution_name() != "" and OS.get_distribution_name() != OS.get_name():
		info.os += " (%s)" % OS.get_distribution_name()
	info.device = OS.get_model_name()
	info.cpu = "%s × %d" % [OS.get_processor_name(), OS.get_processor_count()]
	var mem := int(OS.get_memory_info().get("physical", -1))
	info.memory_mb = mem >> 20 if mem > 0 else -1
	info.gpu = "%s %s" % [RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_name()]
	info.gpu_api = RenderingServer.get_video_adapter_api_version()
	info.renderer = "%s / %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name()]
	var hz := DisplayServer.screen_get_refresh_rate()
	info.screen = "%s @ %s Hz, window %s" % [DisplayServer.screen_get_size(), "%.0f" % hz if hz > 0.0 else "?", DisplayServer.window_get_size()]
	info.locale = OS.get_locale()
	var rec := GfxDetect.load_record()
	if rec.is_empty():
		info.graphics_tier = "not detected"
	else:
		var t := int(rec.get("tier", -1))
		info.graphics_tier = ("%d %s" % [t, GfxDetect.TIER_NAMES[clampi(t, 0, GfxDetect.LAST)]]) if t >= 0 else "none"
		for k in ["manual", "cancelled"]:
			if rec.has(k):
				info.graphics_tier += ", " + k
	info.options = options_summary()


static func options_summary() -> String:
	var parts := PackedStringArray()
	for k in Array(GfxDetect.keys()) + ["display_mode", "resolution", "fps_limit", "vsync", "auto_graphics"]:
		if GameData.options.has(k):
			parts.append("%s=%d" % [k.trim_prefix("gfx_"), GameData.option(k)])
	return " ".join(parts)


## Markers left by sessions that did not quit cleanly (not `own_pid`, not an
## instance still running) are removed; returns the newest one that was in the
## foreground (a crash), with "log" = its log file, or {}.
static func scan(own_pid: int) -> Dictionary:
	var best := {}
	if not DirAccess.dir_exists_absolute(DIR):
		return best
	for f in DirAccess.get_files_at(DIR):
		if not (f.begins_with(MARK_PREFIX) and f.ends_with(".cfg")):
			continue
		var cfg := ConfigFile.new()
		var path := DIR.path_join(f)
		if cfg.load(path) != OK:
			DirAccess.remove_absolute(path)
			continue
		var pid := int(cfg.get_value("session", "pid", -1))
		if instance and path == instance._marker:
			continue   # this session's own
		if pid != own_pid and alive(pid):
			continue   # another game window
		var d := {}
		for k in cfg.get_section_keys("session"):
			d[k] = cfg.get_value("session", k)
		DirAccess.remove_absolute(path)
		if String(d.get("state", "")) != "foreground":
			GameData.trace("previous session %s was closed by the system in the background (not a crash)" % d.get("session", "?"))
			continue
		if handheld and String(d.get("focus", "")) == "out":
			GameData.trace("previous session %s was closed without the focus, from the recent apps (not a crash)" % d.get("session", "?"))
			continue
		if best.is_empty() or String(d.get("updated", "")) > String(best.get("updated", "")):
			best = d
	if not best.is_empty():
		best.log = find_log(String(best.get("session", "")))
		GameData.trace("previous session %s ended unexpectedly in %s; its log: %s" % [best.get("session", "?"), best.get("zone", "?"), best.log])
	return best


## A process `pid` runs (Linux / Android: /proc; OS.is_process_running knows
## only child processes). Elsewhere a second game window's marker counts as left.
static func alive(pid: int) -> bool:
	return pid > 0 and (OS.has_feature("linuxbsd") or OS.has_feature("android")) and DirAccess.dir_exists_absolute("/proc/%d" % pid)


## The rotated log that holds session `sid` (its first trace line), else the
## newest older log; "" if none.
static func find_log(sid: String) -> String:
	var logs := older_logs()
	for p: String in logs.slice(0, 4):
		var fa := FileAccess.open(p, FileAccess.READ)
		if fa and fa.get_buffer(mini(fa.get_length(), 65536)).get_string_from_utf8().contains("session " + sid):
			return p
	return logs[0] if not logs.is_empty() else ""


## The logs of earlier runs (Godot renames godot.log at each start), newest first.
static func older_logs() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		return out
	for f in DirAccess.get_files_at(LOG_DIR):
		if f.ends_with(".log") and f != LOG_FILE.get_file():
			out.append(LOG_DIR.path_join(f))
	out.sort_custom(func(a, b): return FileAccess.get_modified_time(a) > FileAccess.get_modified_time(b))
	return out


static func tail(path: String, n: int) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return "(no log file)\n"
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return "(log not readable)\n"
	var size := fa.get_length()
	var take := mini(size, n * 400)
	fa.seek(size - take)
	var lines := fa.get_buffer(take).get_string_from_utf8().split("\n")
	if take < size and lines.size() > 0:
		lines.remove_at(0)   # a partial line
	if lines.size() > n:
		lines = lines.slice(lines.size() - n)
	return "\n".join(lines)


## Called by GameData.trace: the last step and the current zone go into the marker.
static func note(what: String) -> void:
	if instance == null or instance._marker.is_empty() or instance._done:
		return
	var i := instance.info
	i.last = what
	if what.begins_with("zone ready "):
		i.zone = what.trim_prefix("zone ready ").get_slice(" ", 0)
	elif what.begins_with("zone load "):
		i.zone = what.trim_prefix("zone load ").get_slice(" ", 0) + " (loading)"
	elif what == "back to main menu":
		i.zone = "(menu)"
	elif what.begins_with("graphics detection: tier") or what.begins_with("graphics watchdog"):
		instance._collect()
	elif what.begins_with("option "):
		i.options = options_summary()
	instance._write()


func _write() -> void:
	if _marker.is_empty() or _done:
		return
	info.updated = Time.get_datetime_string_from_system(false, true)
	info.uptime_s = Time.get_ticks_msec() / 1000
	var cfg := ConfigFile.new()
	for k: String in info:
		cfg.set_value("session", k, info[k])
	cfg.save(_marker)


func _notification(what: int) -> void:
	if not enabled or _marker.is_empty():
		return
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			# Android / iOS: from here the system may kill the app at any time;
			# the trace line also flushes the log (flush_stdout_on_print).
			info.state = "background"
			GameData.trace("app paused (background)")
		NOTIFICATION_APPLICATION_RESUMED:
			info.state = "foreground"
			GameData.trace("app resumed")
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			info.focus = "out"
			if handheld:
				GameData.trace("app focus out")   # writes the marker, flushes the log
			else:
				_write()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			info.focus = "in"
			_write()
		NOTIFICATION_WM_CLOSE_REQUEST:
			if get_tree().auto_accept_quit:
				clean_exit()
		NOTIFICATION_OS_MEMORY_WARNING:
			GameData.trace("system memory warning")


func _exit_tree() -> void:
	clean_exit()


## The session ends normally: its marker goes.
func clean_exit() -> void:
	if _done or _marker.is_empty():
		return
	GameData.trace("clean exit")
	_done = true
	DirAccess.remove_absolute(_marker)


## Test hook: as if the system killed the paused app (the marker stays);
## `focus_out`: the app had lost the focus (the recent-apps screen).
func simulate_kill(paused: bool, focus_out := false) -> void:
	info.state = "background" if paused else "foreground"
	info.focus = "out" if focus_out else "in"
	_write()
	_done = true


# ------------------------------------------------------------------ reports

static func _info_text(title: String, d: Dictionary) -> String:
	var s := "== %s ==\n" % title
	for k in ["session", "version", "engine", "os", "device", "cpu", "memory_mb", "gpu", "gpu_api", "renderer",
			"screen", "locale", "graphics_tier", "options", "started", "updated", "uptime_s", "zone", "last", "state", "focus"]:
		if d.has(k):
			s += "%s: %s\n" % [k, d[k]]
	return s


## The report: the previous session that ended unexpectedly (`prev`, may be
## {}) with its log, this session's info and log; `lines` per log.
func report_text(prev: Dictionary, lines: int) -> String:
	_collect()
	var s := "Cursed Lands report, %s\n\n" % Time.get_datetime_string_from_system(false, true)
	if not prev.is_empty():
		s += _info_text("Previous session (ended unexpectedly)", prev)
		s += "\n== Log of the previous session: %s ==\n%s\n" % [String(prev.get("log", "")).get_file(), tail(String(prev.get("log", "")), lines)]
	s += "\n" + _info_text("This session", info)
	if prev.is_empty():
		var older := older_logs()
		if not older.is_empty():
			s += "\n== Log of the previous run: %s ==\n%s\n" % [String(older[0]).get_file(), tail(older[0], lines / 2)]
	s += "\n== Log of this session: %s ==\n%s\n" % [LOG_FILE.get_file(), tail(LOG_FILE, lines if prev.is_empty() else lines / 4)]
	return s


## Folders a player can open, best first.
static func save_dirs() -> PackedStringArray:
	var out := PackedStringArray()
	if save_dir_override != "":
		out.append(save_dir_override)
		return out
	if OS.has_feature("android"):
		out.append(OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS, true))     # /storage/emulated/0/Download
		out.append(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS, false))    # Android/data/<package>/files/Documents
	else:
		out.append(OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS))
		out.append(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS))
	out.append(ProjectSettings.globalize_path("user://reports"))
	return out


## Writes the report; returns the file's full path, or "" if no folder took it.
func save_report(prev: Dictionary) -> String:
	var text := report_text(prev, FILE_LINES)
	var file := "CursedLands-report-%s.txt" % Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "").replace("T", "-")
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), file, "text/plain")
		GameData.trace("report downloaded: " + file)
		return file
	for d in save_dirs():
		if d.is_empty():
			continue
		if not DirAccess.dir_exists_absolute(d):
			if d != save_dir_override and not d.ends_with("reports"):
				continue   # never create shared folders
			DirAccess.make_dir_recursive_absolute(d)
		var path := d.path_join(file)
		var fa := FileAccess.open(path, FileAccess.WRITE)
		if fa == null:
			GameData.trace("report: %s not writable (%s)" % [d, error_string(FileAccess.get_open_error())])
			continue
		fa.store_string(text)
		fa.close()
		if FileAccess.file_exists(path):
			GameData.trace("report saved: " + path)
			return path
	return ""


func copy_report(prev: Dictionary) -> void:
	DisplayServer.clipboard_set(report_text(prev, CLIP_LINES))
	GameData.trace("report copied to the clipboard")
