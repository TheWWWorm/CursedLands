class_name EIInnoSetup
extends RefCounted
## Reads the original game's installer (GOG setup_evil_islands_*.original, Inno
## Setup 5.5.0 unicode) so the player can hand the remake the installer
## instead of an installed game folder. Nothing is run: the files are
## decompressed straight from the installer.
##
## Layout (as innoextract reads it):
## - the loader's offset table ("rDlPtS\xcd\xe6\xd7\x7b\x0b\x2a", version 1):
##   total size, the setup original's offset / size / CRC, Offset0 (setup header)
##   and Offset1 (file data);
## - at Offset0 the 64-byte version string, then two blocks (u32 CRC, u32
##   size, u8 compressed; the data in 4096-byte pieces each after a CRC32),
##   LZMA1-compressed: the setup header with all its entry lists, and the data
##   entries (74 bytes each: first / last slice, chunk start, chunk
##   sub-offset u64, original size u64, chunk compressed size u64, SHA-1,
##   file time, version, u16 flags);
## - at Offset1 + chunk start: "zlb\x1a" and the chunk's LZMA1 stream.
## File entries (destination name → data entry) are ten strings (source,
## destination, font, strong assembly name, components, tasks, languages,
## check, after / before install), a 20-byte Windows version range, then the
## data entry index, attributes, external size, permissions, flags and type.
## They are found as the longest run of well-formed entries that starts at a
## "{app}" destination, which avoids decoding every other entry list.

const OFFSET_MAGIC := [0x72, 0x44, 0x6c, 0x50, 0x74, 0x53, 0xcd, 0xe6, 0xd7, 0x7b, 0x0b, 0x2a]
const CHUNK_MAGIC := [0x7a, 0x6c, 0x62, 0x1a]   # "zlb\x1a"
const DATA_ENTRY := 74
## Data entry flags (u16): CallInstructionOptimized (x86 call filter, only the
## executables) and ChunkCompressed.
const FLAG_CALL_FILTER := 1 << 4
const FLAG_COMPRESSED := 1 << 7

var path := ""
var error := ""
var version := ""
var offset1 := 0
## Data entries: {start, sub, size, packed, sha1, flags}.
var chunks: Array = []
## Files to write: {name (relative, "/"-separated), chunk}.
var files: Array = []


static func open(file: String) -> EIInnoSetup:
	var s := EIInnoSetup.new()
	s.path = file
	s.error = s._read_header()
	return s


func _read_header() -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "Cannot open the installer."
	# The offset table sits in the loader, within its first few megabytes.
	var head := f.get_buffer(mini(f.get_length(), 8 << 20))
	var at := _find(head, OFFSET_MAGIC)
	if at < 0:
		return "Not an Inno Setup installer (no offset table)."
	var t := at + 12
	if head.decode_u32(t) != 1:
		return "Unsupported installer loader."
	var offset0 := head.decode_u32(t + 20)
	offset1 = head.decode_u32(t + 24)
	f.seek(offset0)
	version = f.get_buffer(64).get_string_from_ascii()
	if not version.begins_with("Inno Setup Setup Data (5.5"):
		return "Unsupported installer version: %s" % version
	var header := _block(f)
	var data := _block(f)
	if header.is_empty() or data.is_empty():
		return "Could not read the installer header."
	for i in data.size() / DATA_ENTRY:
		var e := i * DATA_ENTRY
		chunks.append({"start": data.decode_u32(e + 8), "sub": data.decode_u64(e + 12),
			"size": data.decode_u64(e + 20), "packed": data.decode_u64(e + 28),
			"sha1": data.slice(e + 36, e + 56), "flags": data.decode_u16(e + 72)})
	_find_files(header)
	if files.is_empty():
		return "No game files found in the installer."
	var names := files.map(func(x): return x.name.to_lower())
	for rel: String in GameData.REQUIRED:
		if not rel.to_lower() in names:
			return "The installer does not contain %s." % rel
	return ""


## One setup-0 block: CRC, size, compressed flag, then 4096-byte pieces each
## after its CRC32.
func _block(f: FileAccess) -> PackedByteArray:
	f.get_32()
	var size := f.get_32()
	var packed := f.get_8() != 0
	var raw := f.get_buffer(size)
	var body := PackedByteArray()
	var p := 0
	while p + 4 < raw.size():
		var n := mini(4096, raw.size() - p - 4)
		body.append_array(raw.slice(p + 4, p + 4 + n))
		p += 4 + n
	return EILzma.decode(body, 0, body.size(), -1) if packed else body


func _find_files(h: PackedByteArray) -> void:
	var app := "{app}".to_utf16_buffer()
	var best_start := -1
	var best_n := 0
	var covered := -1
	var i := 8
	while i < h.size() - app.size():
		if h[i] == 0x7b and h[i + 1] == 0 and h[i + 2] == 0x61 and i - 8 > covered \
				and h.slice(i, i + app.size()) == app:
			# The destination's length is at i − 4, the (empty) source before it.
			var q := i - 8
			var n := 0
			while true:
				var r := _entry(h, q)
				if r.is_empty():
					break
				n += 1
				q = r.next
			if n > best_n:
				best_n = n
				best_start = i - 8
			if n > 0:
				covered = q
		i += 1
	var q := best_start
	var seen := {}
	while best_start >= 0:
		var r := _entry(h, q)
		if r.is_empty():
			break
		q = r.next
		var name: String = r.dest
		if not name.begins_with("{app}\\") or name.ends_with("\\") or r.loc >= chunks.size():
			continue
		name = name.trim_prefix("{app}\\").replace("\\", "/")
		if name.begins_with("__support/") or seen.has(name.to_lower()):
			continue
		if int(chunks[r.loc].flags) & FLAG_CALL_FILTER or name.get_extension().to_lower() in ["exe", "dll", "asi"]:
			continue   # executables; the remake never reads them (several the original variants)
		seen[name.to_lower()] = true
		# Lower case: Windows paths are case-insensitive and the editions differ
		# (English "res/", German / Russian "Res/", "Config/ai.reg" beside
		# "config/keyboard.ini"); the remake reads lower-case paths.
		files.append({"name": name.to_lower(), "chunk": r.loc})


func _entry(h: PackedByteArray, q: int) -> Dictionary:
	var dest := ""
	for k in 10:
		if q + 4 > h.size():
			return {}
		var n := h.decode_u32(q)
		if n > 8000 or n % 2 or q + 4 + n > h.size():
			return {}
		if k == 1:
			dest = h.slice(q + 4, q + 4 + n).get_string_from_utf16()
		q += 4 + n
	q += 20
	if q + 23 > h.size():
		return {}
	var loc := h.decode_u32(q)
	if (loc >= chunks.size() and loc != 0xFFFFFFFF) or h[q + 22] > 3:
		return {}
	return {"dest": dest, "loc": loc, "next": q + 23}


static func _find(b: PackedByteArray, pat: Array) -> int:
	var i := b.find(pat[0])
	while i >= 0 and i + pat.size() <= b.size():
		var ok := true
		for k in range(1, pat.size()):
			if b[i + k] != pat[k]:
				ok = false
				break
		if ok:
			return i
		i = b.find(pat[0], i + 1)
	return -1


# ------------------------------------------------------------------ extraction

var _mutex := Mutex.new()
var _queue: Array = []        # chunk indexes, largest first
var _decoders: Array = []     # live EILzma (for progress)
var _written := 0             # bytes of finished chunks
var _total := 0
var _threads: Array = []
var _dest := ""
var _failed := ""
var _cancel := false


## Starts unpacking every game file under `dest` on background threads;
## poll progress() / finished() / failure().
func extract(dest: String) -> void:
	_dest = dest
	var by_chunk := {}
	for f: Dictionary in files:
		by_chunk[f.chunk] = true
	_queue = by_chunk.keys()
	_queue.sort_custom(func(a, b): return chunks[a].size > chunks[b].size)
	_total = 0
	for c in _queue:
		_total += int(chunks[c].size)
	for i in clampi(OS.get_processor_count() - 1, 1, 8):
		var t := Thread.new()
		t.start(_work)
		_threads.append(t)


## 0..1 by uncompressed bytes.
func progress() -> float:
	_mutex.lock()
	var n := _written
	for d: EILzma in _decoders:
		n += d.done
	_mutex.unlock()
	return float(n) / maxf(1.0, _total)


func finished() -> bool:
	for t: Thread in _threads:
		if t.is_alive():
			return false
	for t: Thread in _threads:
		t.wait_to_finish()
	_threads.clear()
	return true


func failure() -> String:
	return _failed


func cancel() -> void:
	_mutex.lock()
	_cancel = true
	for d: EILzma in _decoders:
		d.abort = true
	_mutex.unlock()


func _work() -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	while true:
		_mutex.lock()
		var c = null if _queue.is_empty() or _cancel or _failed != "" else _queue.pop_front()
		_mutex.unlock()
		if c == null:
			return
		var err := _unpack(f, c)
		if err:
			_mutex.lock()
			_failed = err
			_mutex.unlock()


func _unpack(f: FileAccess, c: int) -> String:
	var ch: Dictionary = chunks[c]
	f.seek(offset1 + int(ch.start))
	var magic := f.get_buffer(4)
	if Array(magic) != CHUNK_MAGIC:
		return "Bad data chunk %d in the installer." % c
	var packed := f.get_buffer(int(ch.packed))
	var out: PackedByteArray
	var size := int(ch.sub) + int(ch.size)
	if int(ch.flags) & FLAG_COMPRESSED:
		var d := EILzma.new()
		_mutex.lock()
		_decoders.append(d)
		_mutex.unlock()
		out = d.run2(packed, 0, packed.size(), size)
		_mutex.lock()
		_decoders.erase(d)
		_written += int(ch.size)
		_mutex.unlock()
		if d.abort:
			return ""
	else:
		out = packed
		_mutex.lock()
		_written += int(ch.size)
		_mutex.unlock()
	out = out.slice(int(ch.sub), size)
	var sha := HashingContext.new()
	sha.start(HashingContext.HASH_SHA1)
	sha.update(out)
	if sha.finish() != ch.sha1:
		return "Checksum mismatch in the installer (chunk %d)." % c
	for fl: Dictionary in files:
		if fl.chunk != c:
			continue
		var target := _dest.path_join(fl.name)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var w := FileAccess.open(target, FileAccess.WRITE)
		if w == null:
			return "Cannot write %s." % target
		w.store_buffer(out)
	return ""
