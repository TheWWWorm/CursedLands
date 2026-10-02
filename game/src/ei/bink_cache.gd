class_name EIBinkCache
extends RefCounted
## One-time conversion of an original .bik movie into the player's movie cache
## (user://movies/<name>.eiv), done on a background thread by the native
## decoder (EIBink, EIBinkAudio): GDScript cannot decode the longest movies in
## real time, so every frame is stored as a JPEG of its packed Y / U / V planes
## (EIBink.yuv_image) and the audio as PCM16. The movie player can already
## stream the frames that are done while the conversion runs.
##
## .eiv layout (little endian):
##   0  "EIV1", u32 complete (0 while converting), u32 width, height, frames,
##      fps_num, fps_den, audio_rate, audio_channels, u32 reserved
##   40 u64 audio_offset, u64 audio_size, u64 index_offset
##   64 frame JPEGs back to back, then the PCM16 audio, then the index:
##      frames + 1 u64 offsets (frame i = [off[i], off[i+1]))

const MAGIC := 0x31564945  # "EIV1"
const HEADER := 64
const JPG_QUALITY := 0.85

var width := 0
var height := 0
var frame_count := 0
var fps_num := 25
var fps_den := 1
var audio_rate := 0
var audio_channels := 0
var path := ""  ## the .eiv being written
var ok := false  ## conversion finished and the cache is complete
var failed := false
var cancel := false  ## set to stop the conversion (the file stays incomplete)
var ms_per_frame := 0.0  ## measured conversion speed
## Prefix sums of the frames' video bytes (+ a fixed part): decoding time is
## roughly proportional, which lets the player predict the conversion.
var cum_cost := PackedInt64Array()

var _mutex := Mutex.new()
var _offsets := PackedInt64Array()
var _done := 0
var _pcm := PackedByteArray()
var _audio_ready := false
var _thread: Thread
var _started := 0
var _serial_running := false


## Starts converting `src` into `dst` on a background thread.
func start(src: String, dst: String) -> void:
	EIBink.init_tables()
	path = dst
	_started = Time.get_ticks_msec()
	if not Portability.threads():
		_serial_running = true
		_serial.call_deferred(src, dst)
		return
	_thread = Thread.new()
	_thread.start(convert.bind(src, dst), Thread.PRIORITY_LOW)


func is_running() -> bool:
	return _serial_running or (_thread != null and _thread.is_alive())


func _serial(src: String, dst: String) -> void:
	# Yield between frames on the single-thread Web export. No hidden workers,
	# and only the requested movie is converted. The skip control stays live.
	var decoder := EIBink.new()
	if not decoder.open(src):
		failed = true
		_serial_running = false
		return
	width = decoder.width
	height = decoder.height
	frame_count = decoder.frame_count
	fps_num = decoder.fps_num
	fps_den = decoder.fps_den
	cum_cost = PackedInt64Array([0])
	for i in frame_count: cum_cost.append(cum_cost[i] + decoder.frame_size(i) + 2000)
	var audio: EIBinkAudio
	if not decoder.audio_tracks.is_empty() and not decoder.audio_tracks[0].get("dct", false):
		audio = EIBinkAudio.new(decoder.audio_tracks[0], decoder.revision)
		audio_rate = decoder.audio_tracks[0].rate
		audio_channels = decoder.audio_tracks[0].channels
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	var file := FileAccess.open(dst, FileAccess.WRITE)
	if file == null:
		failed = true
		_serial_running = false
		return
	_write_header(file, false, 0, 0, 0)
	_offsets = PackedInt64Array([HEADER])
	for i in frame_count:
		if cancel: break
		var data := decoder.frame_data(i)
		if audio: _pcm.append_array(audio.decode_packet(decoder.audio_packet(data)))
		decoder.decode_frame(data, EIBink.PLANES_ALL)
		file.store_buffer(decoder.yuv_image(null).save_jpg_to_buffer(JPG_QUALITY))
		if file.get_error() != OK:
			failed = true
			break
		_offsets.append(file.get_position())
		_done = i + 1
		await (Engine.get_main_loop() as SceneTree).process_frame
	if not cancel and not failed:
		var audio_offset := file.get_position()
		file.store_buffer(_pcm)
		var index_offset := file.get_position()
		for offset in _offsets: file.store_64(offset)
		_write_header(file, true, audio_offset, _pcm.size(), index_offset)
		ok = file.get_error() == OK
		failed = not ok
		_audio_ready = true
	file.close()
	_serial_running = false


## Waits for the conversion thread (call after cancel, or when it finished).
func finish() -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null


func frames_done() -> int:
	_mutex.lock()
	var n := _done
	_mutex.unlock()
	return n


## Byte range of frame i in the file (valid once i < frames_done()).
func frame_span(i: int) -> Vector2i:
	_mutex.lock()
	var r := Vector2i(_offsets[i], _offsets[i + 1])
	_mutex.unlock()
	return r


## The whole audio track once it is decoded (empty before / without audio).
func audio_pcm() -> PackedByteArray:
	_mutex.lock()
	var r := _pcm if _audio_ready else PackedByteArray()
	_mutex.unlock()
	return r


func audio_ready() -> bool:
	_mutex.lock()
	var r := _audio_ready
	_mutex.unlock()
	return r


## Seconds since the conversion started.
func elapsed() -> float:
	return (Time.get_ticks_msec() - _started) / 1000.0


## Blocking conversion (the thread body; also usable directly by tools).
func convert(src: String, dst: String) -> bool:
	path = dst
	if _started == 0:
		_started = Time.get_ticks_msec()
	var a := EIBink.new()
	if not a.open(src):
		push_warning("movie %s: %s" % [src, a.error])
		failed = true
		return false
	var b: EIBink = null
	if a.can_split():  # chroma planes on a second thread
		b = EIBink.new()
		b.open(src)
	var cum := PackedInt64Array([0])
	for i in a.frame_count:
		cum.append(cum[i] + a.frame_size(i) + 2000)
	cum_cost = cum
	width = a.width
	height = a.height
	frame_count = a.frame_count
	fps_num = a.fps_num
	fps_den = a.fps_den
	var audio_task := -1
	if not a.audio_tracks.is_empty() and not a.audio_tracks[0].get("dct", false):
		audio_rate = a.audio_tracks[0].rate
		audio_channels = a.audio_tracks[0].channels
		audio_task = WorkerThreadPool.add_task(_decode_audio.bind(src), false, "bink audio")
	else:
		_mutex.lock()
		_audio_ready = true
		_mutex.unlock()
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		push_warning("movie cache: cannot write " + dst)
		failed = true
		if audio_task >= 0:
			WorkerThreadPool.wait_for_task_completion(audio_task)
		return false
	_write_header(f, false, 0, 0, 0)
	_mutex.lock()
	_offsets = PackedInt64Array([HEADER])
	_mutex.unlock()
	var t0 := Time.get_ticks_usec()
	# frame i: luma here, chroma on a pool thread, while the JPEG of frame i - 1
	# is encoded on another one
	var enc_task := -1
	var enc := [null]
	for i in frame_count + 1:
		if cancel:
			break
		var dec_task := -1
		if i < frame_count:
			var data := a.frame_data(i)
			if b:
				dec_task = WorkerThreadPool.add_task(b.decode_frame.bind(data, EIBink.PLANES_UV), false, "bink chroma")
			a.decode_frame(data, EIBink.PLANES_Y if b else EIBink.PLANES_ALL)
		if dec_task >= 0:
			WorkerThreadPool.wait_for_task_completion(dec_task)
		if enc_task >= 0:
			WorkerThreadPool.wait_for_task_completion(enc_task)
			enc_task = -1
			f.store_buffer(enc[0])
			f.flush()
			_mutex.lock()
			_offsets.append(f.get_position())
			_done = i
			_mutex.unlock()
		if i < frame_count:
			enc_task = WorkerThreadPool.add_task(_encode.bind(a.yuv_image(b), enc), false, "movie jpeg")
	if enc_task >= 0:
		WorkerThreadPool.wait_for_task_completion(enc_task)
	ms_per_frame = (Time.get_ticks_usec() - t0) / 1000.0 / maxi(_done, 1)
	if audio_task >= 0:
		WorkerThreadPool.wait_for_task_completion(audio_task)
	if cancel:
		f.close()
		return false
	var pcm := audio_pcm()
	var audio_off := f.get_position()
	f.store_buffer(pcm)
	var index_off := f.get_position()
	for o in _offsets:
		f.store_64(o)
	_write_header(f, true, audio_off, pcm.size(), index_off)
	f.close()
	ok = true
	return true


static func _encode(img: Image, out: Array) -> void:
	out[0] = img.save_jpg_to_buffer(JPG_QUALITY)


func _write_header(f: FileAccess, complete: bool, audio_off: int, audio_size: int, index_off: int) -> void:
	f.seek(0)
	f.store_32(MAGIC)
	f.store_32(1 if complete else 0)
	for v in [width, height, frame_count, fps_num, fps_den, audio_rate, audio_channels, 0]:
		f.store_32(v)
	f.store_64(audio_off)
	f.store_64(audio_size)
	f.store_64(index_off)
	while f.get_position() < HEADER:
		f.store_8(0)
	if complete:
		f.seek_end()


func _decode_audio(src: String) -> void:
	var bk := EIBink.new()
	var pcm := PackedByteArray()
	if bk.open(src):
		var au := EIBinkAudio.new(bk.audio_tracks[0], bk.revision)
		for i in bk.frame_count:
			if cancel:
				break
			pcm.append_array(au.decode_packet(bk.audio_packet(bk.frame_data(i))))
	_mutex.lock()
	_pcm = pcm
	_audio_ready = true
	_mutex.unlock()


## A finished cache file opened for playback, or null when `file` is missing,
## incomplete or not a cache. Returns {file, width, height, frames, fps,
## offsets, pcm, audio_rate, audio_channels}.
static func open_cache(file: String) -> Dictionary:
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null or f.get_length() < HEADER or f.get_32() != MAGIC or f.get_32() != 1:
		return {}
	var r := {"file": f}
	for k in ["width", "height", "frames", "fps_num", "fps_den", "audio_rate", "audio_channels"]:
		r[k] = f.get_32()
	f.get_32()
	var audio_off := f.get_64()
	var audio_size := f.get_64()
	var index_off := f.get_64()
	var n: int = r.frames
	if index_off + (n + 1) * 8 > f.get_length():
		return {}
	f.seek(index_off)
	var offs := PackedInt64Array()
	offs.resize(n + 1)
	for i in n + 1:
		offs[i] = f.get_64()
	r.offsets = offs
	f.seek(audio_off)
	r.pcm = f.get_buffer(audio_size)
	return r
