class_name EIAudio
extends RefCounted
## Sound data read from the player's installation: sfx.res (IMA ADPCM / PCM
## WAVs), speech.res (briefing voice MP3s), stream/*.mp3 (music).

const INDEX_TABLE := [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]
const STEP_TABLE := [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60,
	66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494,
	544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024,
	3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289,
	16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767]

static var _sfx: EIResArchive
static var _speech: EIResArchive
static var _cache := {}
static var _dirs := {}
static var _music_reg := {}


static func _archive(name: String) -> EIResArchive:
	if GameData.root.is_empty():
		return null
	return EIResArchive.open_path(GameData.res_path(name))


## A sound from sfx.res by path ("tools\\gate.wav"), or null.
static func sfx(path: String) -> AudioStreamWAV:
	path = path.to_lower().replace("\\", "/")
	if _cache.has(path):
		return _cache[path]
	_pre_lock.lock()
	var pre: bool = _pre.has(path)
	var ps: AudioStreamWAV = _pre.get(path)
	_pre.erase(path)
	_pre_lock.unlock()
	if pre:
		_cache[path] = ps
		return ps
	if _sfx == null:
		_sfx = _archive("sfx.res")
	var s: AudioStreamWAV = null
	if _sfx and _sfx.has(path):
		s = decode_wav(_sfx.read(path))
	_cache[path] = s
	return s


static var _pre_lock := Mutex.new()
static var _pre := {}   # path -> AudioStreamWAV decoded by prefetch(), not yet in _cache
static var _pre_tasks := PackedInt64Array()
static var _pre_stop := false


## Decodes sfx.res files on a worker thread so their first play does not
## stall a frame (decoding takes ~1-50 ms a file): `paths` are files
## ("x\\y.wav") or folders (every file directly inside). sfx() takes them
## from there; one it needs before the worker got to it is decoded as before.
static func prefetch(paths: PackedStringArray) -> void:
	if GameData.root.is_empty():
		return
	var files := PackedStringArray()
	for p in paths:
		if p.to_lower().ends_with(".wav"):
			var f := p.to_lower().replace("\\", "/")
			if not _cache.has(f) and not files.has(f):
				files.append(f)
		else:
			for f in sfx_dir(p):
				if not _cache.has(f) and not files.has(f):
					files.append(f)
	if files.is_empty():
		return
	if not Portability.threads():
		# No worker threads (the web export): the zone start runs behind the
		# loading screen, so decode them there rather than at the first play,
		# which stalled the running game (a bridge read and a decode each).
		for f in files:
			sfx(f)
		return
	_tables()   # filled here, not by two threads at once
	var left := PackedInt64Array()   # every task is waited for once
	for t in _pre_tasks:
		if WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
		else:
			left.append(t)
	_pre_tasks = left
	# A few workers, each taking every n-th file in list order.
	var n := clampi(OS.get_processor_count() / 2, 1, 4)
	for k in n:
		var part := PackedStringArray()
		for i in range(k, files.size(), n):
			part.append(files[i])
		_pre_tasks.append(WorkerThreadPool.add_task(_prefetch_job.bind(GameData.res_path("sfx.res"), part), false, "sfx prefetch"))


## At quit (Main._exit_tree): stops and waits for the prefetch workers and
## drops the decoded streams while the engine's servers are still up.
static func shutdown() -> void:
	_pre_stop = true
	for t in _pre_tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_pre_tasks.clear()
	_pre_lock.lock()
	_pre.clear()
	_pre_lock.unlock()
	_cache.clear()
	_pre_stop = false


static func _prefetch_job(arc_path: String, files: PackedStringArray) -> void:
	var arc := EIResArchive.open_path(arc_path)   # its own file handle
	if arc == null:
		return
	for f in files:
		if _pre_stop:
			return
		_pre_lock.lock()
		var have := _pre.has(f)
		_pre_lock.unlock()
		if have or not arc.has(f):
			continue
		var s := decode_wav(arc.read(f))
		_pre_lock.lock()
		_pre[f] = s
		_pre_lock.unlock()


## All sfx.res files directly inside `dir` ("animals\\wolf\\attack").
static func sfx_dir(dir: String) -> PackedStringArray:
	dir = dir.to_lower().replace("\\", "/").trim_suffix("/") + "/"
	if _dirs.has(dir):
		return _dirs[dir]
	if _sfx == null:
		_sfx = _archive("sfx.res")
	var out := PackedStringArray()
	if _sfx:
		for n: String in _sfx.entries:
			if n.begins_with(dir) and not n.substr(dir.length()).contains("/"):
				out.append(n)
	out.sort()
	_dirs[dir] = out
	return out


static func sfx_random(dir: String) -> AudioStreamWAV:
	var files := sfx_dir(dir)
	return sfx(files[randi() % files.size()]) if not files.is_empty() else null


## Voice line `n` of briefing `id` (speech.res "briefing\\<id>\\<n>.mp3").
static func speech(id: String, n: int) -> AudioStreamMP3:
	if _speech == null:
		_speech = _archive("speech.res")
	# English / German the original: "briefing\\%s\\%d.mp3". The
	# Russian the original formats "%s\\briefing\\%s\\%d.mp3" with "t" or "s"
	# picked at random (rand · 2 / 32767 into the table {"t", "s"}
	# ); its speech.res holds both sets, byte-identical in the GOG copy.
	var key := "briefing/%s/%d.mp3" % [id.to_lower(), n]
	if _speech and not _speech.has(key):
		key = ["t/", "s/"][randi() % 2] + key
	if _speech == null or not _speech.has(key):
		return null
	var s := AudioStreamMP3.new()
	s.data = _speech.read(key)
	return s


static func music(name: String) -> AudioStreamMP3:
	var path := music_path(name)
	if path.is_empty():
		return null
	var s := AudioStreamMP3.new()
	s.data = GameFiles.read(path)
	return s


## music.reg: {allod: {Briefing, CalmOpen, CalmDungeon, Combat, Constructor}}.
static func music_table() -> Dictionary:
	if _music_reg.is_empty() and GameData.root:
		_music_reg = EIRegFile.parse(GameFiles.read(GameData.root.path_join("res/music.reg")))
	return _music_reg


static func decode_wav(d: PackedByteArray) -> AudioStreamWAV:
	if d.size() < 44 or d.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var p := 12
	var fmt := 0
	var channels := 1
	var rate := 22050
	var align := 0
	var bits := 16
	var data := PackedByteArray()
	while p + 8 <= d.size():
		var id := d.slice(p, p + 4).get_string_from_ascii()
		var size := d.decode_u32(p + 4)
		if id == "fmt ":
			fmt = d.decode_u16(p + 8)
			channels = d.decode_u16(p + 10)
			rate = d.decode_u32(p + 12)
			align = d.decode_u16(p + 20)
			bits = d.decode_u16(p + 22)
		elif id == "data":
			data = d.slice(p + 8, mini(d.size(), p + 8 + size))
		p += 8 + size + (size & 1)
	var s := AudioStreamWAV.new()
	s.mix_rate = rate
	s.stereo = channels == 2
	match fmt:
		1:
			s.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
			if bits == 8:
				for i in data.size():
					data[i] = (data[i] - 128) & 0xff
			s.data = data
		17:
			s.format = AudioStreamWAV.FORMAT_16_BITS
			s.data = _ima_decode(data, align, channels)
		_:
			return null
	return s


## Microsoft IMA ADPCM (blocks with a per-channel header) to 16-bit PCM.
## Written for speed (a first sound used to stall a frame for ~20 ms, up to
## 300 ms for long loops): the step is a table lookup by (index, nibble)
## (_tables, the same arithmetic as _step) and the samples go straight into
## the output bytes.
static func _ima_decode(src: PackedByteArray, align: int, channels: int) -> PackedByteArray:
	if align <= 4 * channels:
		return PackedByteArray()
	_tables()
	var dtab := _diff_tab
	var ntab := _next_tab
	var hdr := 4 * channels
	# Output size: each block gives its header samples plus two per mono body
	# byte, or eight per channel per 4-byte group in stereo.
	var total := 0
	var pos := 0
	while pos + hdr <= src.size():
		var blen := mini(src.size(), pos + align) - pos
		pos += align
		var body := blen - hdr
		total += channels + (body * 2 if channels == 1 else (body / (4 * channels)) * 8 * channels)
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	var o := 0
	pos = 0
	while pos + hdr <= src.size():
		var bend := mini(src.size(), pos + align)
		var start := o
		if channels == 1:
			var pred := src.decode_s16(pos)
			var idx := clampi(src[pos + 2], 0, 88)
			bytes.encode_s16(o, pred)
			o += 2
			for i in range(pos + 4, bend):
				var b := src[i]
				var k := (idx << 4) | (b & 0x0f)
				pred = clampi(pred + dtab[k], -32768, 32767)
				idx = ntab[k]
				bytes.encode_s16(o, pred)
				k = (idx << 4) | (b >> 4)
				pred = clampi(pred + dtab[k], -32768, 32767)
				idx = ntab[k]
				bytes.encode_s16(o + 2, pred)
				o += 4
		else:
			var pred := PackedInt32Array()
			var idx := PackedInt32Array()
			pred.resize(channels)
			idx.resize(channels)
			for c in channels:
				pred[c] = src.decode_s16(pos + c * 4)
				idx[c] = clampi(src[pos + c * 4 + 2], 0, 88)
				bytes.encode_s16(o, pred[c])
				o += 2
			# Stereo: 4 bytes (8 samples) per channel, interleaved.
			var body := pos + hdr
			var groups := (bend - body) / (4 * channels)
			for g in groups:
				for c in channels:
					var p := pred[c]
					var x := idx[c]
					var at := o + c * 2
					for kk in 4:
						var b := src[body + g * 4 * channels + c * 4 + kk]
						var k := (x << 4) | (b & 0x0f)
						p = clampi(p + dtab[k], -32768, 32767)
						x = ntab[k]
						bytes.encode_s16(at, p)
						at += channels * 2
						k = (x << 4) | (b >> 4)
						p = clampi(p + dtab[k], -32768, 32767)
						x = ntab[k]
						bytes.encode_s16(at, p)
						at += channels * 2
					pred[c] = p
					idx[c] = x
				o += 16 * channels
		pos += align
		if start == o:
			break
	return bytes


static var _diff_tab := PackedInt32Array()
static var _next_tab := PackedInt32Array()


## Signed predictor change and next step index for every (index, nibble).
static func _tables() -> void:
	if not _diff_tab.is_empty():
		return
	_diff_tab.resize(89 * 16)
	_next_tab.resize(89 * 16)
	for idx in 89:
		for nib in 16:
			var step: int = STEP_TABLE[idx]
			var diff := step >> 3
			if nib & 4:
				diff += step
			if nib & 2:
				diff += step >> 1
			if nib & 1:
				diff += step >> 2
			_diff_tab[(idx << 4) | nib] = -diff if nib & 8 else diff
			_next_tab[(idx << 4) | nib] = clampi(idx + INDEX_TABLE[nib], 0, 88)


static func _step(pred: int, idx: int, nib: int) -> Vector2i:
	var step: int = STEP_TABLE[idx]
	var diff := step >> 3
	if nib & 4:
		diff += step
	if nib & 2:
		diff += step >> 1
	if nib & 1:
		diff += step >> 2
	pred = clampi(pred - diff if nib & 8 else pred + diff, -32768, 32767)
	idx = clampi(idx + INDEX_TABLE[nib], 0, 88)
	return Vector2i(pred, idx)


## stream/<name>.mp3 of the installation, or "" when there is none.
static func music_path(name: String) -> String:
	var path := GameData.root.path_join("stream/%s.mp3" % name.to_lower())
	return GameFiles.resolve(path) if GameFiles.exists(path) else ""
