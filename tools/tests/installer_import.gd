extends Node
## GOG installer import: the compiled LZMA2 decoder (src/native/installer)
## against the GDScript decoder on real installer chunks, damaged and
## truncated data, misuse of handles, cancelling, a whole extraction with its
## checksums and the decoding speed. Installers (setup_evil_islands*.exe) are
## looked for in --installer-dir= (Android) or CL_INSTALLER_DIR, else beside the
## project folder; without one those checks are skipped.
var checks := 0
var failures := 0
const K := &"InstallerLzmaKernel"

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func installers() -> Array:
	var folder := OS.get_environment("CL_INSTALLER_DIR")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--installer-dir="): folder = arg.trim_prefix("--installer-dir=")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var found := []
	for file in DirAccess.get_files_at(folder):
		if file.to_lower().begins_with("setup_evil_islands") and file.to_lower().ends_with(".exe"):
			found.append(folder.path_join(file))
	return found

func chunk_bytes(setup: EIInnoSetup, c: int) -> PackedByteArray:
	var f := FileAccess.open(setup.path, FileAccess.READ)
	f.seek(setup.offset1 + int(setup.chunks[c].start) + 4)
	return f.get_buffer(int(setup.chunks[c].packed))

func sha1(bytes: PackedByteArray) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA1)
	h.update(bytes)
	return h.finish()

## The GDScript decoder alone: run2 takes the compiled path only for a whole
## buffer from 0, so this passes a copy with one leading byte.
func _gd_only(packed: PackedByteArray, size: int) -> PackedByteArray:
	var shifted := PackedByteArray([0])
	shifted.append_array(packed)
	return EILzma.new().run2(shifted, 1, packed.size(), size)

func _ready() -> void:
	var native := EILzma.native()
	var supported := (OS.has_feature("x86_64") and (OS.has_feature("linux") or OS.has_feature("windows"))) \
		or (OS.has_feature("android") and OS.has_feature("arm64"))
	check(native == supported, "the compiled decoder loads on Linux/Windows x86-64 and Android ARM64 (%s)" % OS.get_name())
	print("native decoder: ", native)
	if native:
		check(int(ClassDB.class_call_static(K, &"step", -1, 10)) == -1, "step on an unknown handle fails")
		check(int(ClassDB.class_call_static(K, &"step", 999, 10)) == -1, "step on an out-of-range handle fails")
		check((ClassDB.class_call_static(K, &"take", 5) as PackedByteArray).is_empty(), "take on an unused handle returns nothing")
		check(int(ClassDB.class_call_static(K, &"open", PackedByteArray(), -5)) == -1, "a negative size is refused")
		var h: int = ClassDB.class_call_static(K, &"open", PackedByteArray([0x10, 0x00]), 0)
		check(h >= 0 and int(ClassDB.class_call_static(K, &"step", h, 0)) == 0, "an empty stream decodes to nothing")
		ClassDB.class_call_static(K, &"take", h)
		var garbage := PackedByteArray()
		garbage.resize(4096)
		for i in garbage.size(): garbage[i] = (i * 151 + 7) & 0xFF
		h = ClassDB.class_call_static(K, &"open", garbage, 1 << 20)
		check(h >= 0 and int(ClassDB.class_call_static(K, &"step", h, 0)) == -1, "random bytes are reported as damaged")
		ClassDB.class_call_static(K, &"take", h)
	var found := installers()
	if found.is_empty(): print("no GOG installer found; installer checks skipped")
	for i in found.size():
		# One full import is enough; the other languages compare chunks only.
		await installer_checks(found[i], native, i == 0 or OS.get_environment("CL_INSTALLER_FULL") == "1")
	print("INSTALLER_IMPORT ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(1 if failures else 0)

func installer_checks(path: String, native: bool, full_import: bool) -> void:
	var tag := path.get_file()
	var setup := EIInnoSetup.open(path)
	check(setup.error.is_empty() and not setup.files.is_empty(), tag + " header reads (%s)" % setup.error)
	if not setup.error.is_empty(): return
	var wanted: Array = []
	for f: Dictionary in setup.files:
		if int(setup.chunks[f.chunk].flags) & EIInnoSetup.FLAG_COMPRESSED and int(setup.chunks[f.chunk].size) > 0 \
				and not wanted.has(f.chunk): wanted.append(f.chunk)
	wanted.sort_custom(func(a, b): return int(setup.chunks[a].packed) < int(setup.chunks[b].packed))
	var sample: Array = wanted.slice(0, 3)
	for c: int in wanted:
		if int(setup.chunks[c].size) >= 512 << 10:
			sample.append(c)
			break
	for c: int in sample:
		var ch: Dictionary = setup.chunks[c]
		var packed := chunk_bytes(setup, c)
		var size := int(ch.sub) + int(ch.size)
		var slow := _gd_only(packed, size)
		check(sha1(slow.slice(int(ch.sub), size)) == ch.sha1, tag + " GDScript decoder matches chunk %d" % c)
		if native:
			var fast := EILzma.decode2(packed, 0, packed.size(), size)
			check(fast == slow, tag + " compiled decoder gives the same %d bytes for chunk %d" % [size, c])
			var bad := packed.duplicate()
			bad[bad.size() / 2] ^= 0x5A
			var broken := EILzma.decode2(bad, 0, bad.size(), size)
			check(broken.size() != size or sha1(broken.slice(int(ch.sub), size)) != ch.sha1, tag + " damaged chunk %d is not accepted" % c)
			var cut := EILzma.decode2(packed.slice(0, packed.size() / 2), 0, packed.size() / 2, size)
			check(cut.size() != size or sha1(cut.slice(int(ch.sub), size)) != ch.sha1, tag + " truncated chunk %d is not accepted" % c)
	if not native or not full_import: return
	var largest: int = wanted[0]
	for c: int in wanted:
		if int(setup.chunks[c].size) > int(setup.chunks[largest].size): largest = c
	var packed := chunk_bytes(setup, largest)
	var t := Time.get_ticks_usec()
	var out := EILzma.decode2(packed, 0, packed.size(), int(setup.chunks[largest].sub) + int(setup.chunks[largest].size))
	var seconds := (Time.get_ticks_usec() - t) / 1e6
	var rate := out.size() / 1048576.0 / maxf(seconds, 0.001)
	print(tag, " largest chunk: %.0f MB in %.2f s (%.0f MB/s)" % [out.size() / 1048576.0, seconds, rate])
	check(sha1(out.slice(int(setup.chunks[largest].sub))) == setup.chunks[largest].sha1, tag + " largest chunk decodes with its checksum")
	check(rate > 5.0, tag + " compiled decoder runs faster than 5 MB/s (%.1f)" % rate)
	out = PackedByteArray()
	packed = PackedByteArray()
	var dest := OS.get_user_data_dir().path_join("installer-cancel")
	var cancelled := EIInnoSetup.open(path)
	cancelled.extract(dest)
	await get_tree().create_timer(0.3).timeout
	cancelled.cancel()
	var waited := 0.0
	while not cancelled.finished() and waited < 20.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	check(waited < 20.0 and cancelled.failure().is_empty(), tag + " cancel stops the import (%.1f s)" % waited)
	_remove(dest)
	dest = OS.get_user_data_dir().path_join("installer-full")
	_remove(dest)
	var full := EIInnoSetup.open(path)
	t = Time.get_ticks_usec()
	full.extract(dest)
	var last := 0.0
	var monotonic := true
	while not full.finished():
		await get_tree().create_timer(0.25).timeout
		var p := full.progress()
		if p + 1e-9 < last: monotonic = false
		last = p
	seconds = (Time.get_ticks_usec() - t) / 1e6
	print(tag, " full import: %d files in %.1f s" % [full.files.size(), seconds])
	check(full.failure().is_empty(), tag + " full import has no failure (%s)" % full.failure())
	check(monotonic and is_equal_approx(full.progress(), 1.0), tag + " progress rises to 1 (%.3f)" % full.progress())
	var missing := 0
	for f: Dictionary in full.files:
		var handle := FileAccess.open(dest.path_join(f.name), FileAccess.READ)
		if handle == null or handle.get_length() != int(full.chunks[f.chunk].size): missing += 1
	check(missing == 0, tag + " every file is written at its size (%d missing or short)" % missing)
	_remove(dest)

func _remove(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder): return
	for file in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder.path_join(file))
	for sub in DirAccess.get_directories_at(folder): _remove(folder.path_join(sub))
	DirAccess.remove_absolute(folder)
