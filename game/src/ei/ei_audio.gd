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
	if _sfx == null:
		_sfx = _archive("sfx.res")
	var s: AudioStreamWAV = null
	if _sfx and _sfx.has(path):
		s = decode_wav(_sfx.read(path))
	_cache[path] = s
	return s


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
	var path := GameData.root.path_join("stream/%s.mp3" % name.to_lower())
	if not FileAccess.file_exists(path):
		return null
	var s := AudioStreamMP3.new()
	s.data = FileAccess.get_file_as_bytes(path)
	return s


## music.reg: {allod: {Briefing, CalmOpen, CalmDungeon, Combat, Constructor}}.
static func music_table() -> Dictionary:
	if _music_reg.is_empty() and GameData.root:
		_music_reg = EIRegFile.parse(FileAccess.get_file_as_bytes(GameData.root.path_join("res/music.reg")))
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
static func _ima_decode(src: PackedByteArray, align: int, channels: int) -> PackedByteArray:
	var out := PackedInt32Array()
	if align <= 4 * channels:
		return PackedByteArray()
	var pos := 0
	while pos + 4 * channels <= src.size():
		var block := src.slice(pos, mini(src.size(), pos + align))
		pos += align
		var pred := []
		var idx := []
		for c in channels:
			pred.append(block.decode_s16(c * 4))
			idx.append(clampi(block[c * 4 + 2], 0, 88))
		var start := out.size()
		for c in channels:
			out.append(pred[c])
		var body := block.slice(4 * channels)
		if channels == 1:
			for b in body:
				for nib in [b & 0x0f, b >> 4]:
					var r := _step(pred[0], idx[0], nib)
					pred[0] = r.x
					idx[0] = r.y
					out.append(r.x)
		else:
			# Stereo: 4 bytes (8 samples) per channel, interleaved.
			var groups := body.size() / (4 * channels)
			for g in groups:
				var chans := []
				for c in channels:
					var samples := []
					for k in 4:
						var b := body[g * 4 * channels + c * 4 + k]
						for nib in [b & 0x0f, b >> 4]:
							var r := _step(pred[c], idx[c], nib)
							pred[c] = r.x
							idx[c] = r.y
							samples.append(r.x)
					chans.append(samples)
				for k in 8:
					for c in channels:
						out.append(chans[c][k])
		if start == out.size():
			break
	var bytes := PackedByteArray()
	bytes.resize(out.size() * 2)
	for i in out.size():
		bytes.encode_s16(i * 2, out[i])
	return bytes


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
