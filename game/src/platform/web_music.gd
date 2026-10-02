extends Node
## MusicSystem's stream player in a browser (the web export).
##
## Godot's web export plays an AudioStreamPlayer as a Web Audio sample: the
## whole MP3 is decoded to PCM on the game's only thread when play() is
## called, 0.3 s for a two-minute track on a fast PC and seconds on a slow
## one, with the old track already stopped (a gap in the music and a frozen
## game at every track change: combat, briefings, calm tracks). Here the
## browser decodes the file off the main thread (decodeAudioData) and plays it
## with its own audio clock, so a busy frame neither delays nor interrupts the
## music. The calls and state MusicSystem uses are those of AudioStreamPlayer:
## play / stop / seek, playing, get_playback_position, volume_db, finished.
## The level follows the Music and Master buses (options volume_stream).

signal finished

const JS := """
(() => {
  if (window.CursedMusic) return true;
  const M = {ctx: null, gain: null, src: null, buf: null, path: '', start: 0, offset: 0,
    playing: false, pending: false, ended: false, token: 0,
    ensure() {
      if (!this.ctx) {
        const C = window.AudioContext || window.webkitAudioContext;
        this.ctx = new C();
        this.gain = this.ctx.createGain();
        this.gain.connect(this.ctx.destination);
        // A context made without a gesture may start suspended (Safari).
        const resume = () => { if (this.ctx.state !== 'running') this.ctx.resume().catch(() => {}); };
        addEventListener('pointerdown', resume, true);
        addEventListener('keydown', resume, true);
      }
      if (this.ctx.state === 'suspended') this.ctx.resume().catch(() => {});
    },
    halt() {
      if (this.src) { this.src.onended = null; try { this.src.stop(); } catch (e) {} this.src.disconnect(); }
      this.src = null;
    },
    begin(at) {
      this.halt();
      const s = this.ctx.createBufferSource(), token = this.token;
      s.buffer = this.buf; s.connect(this.gain);
      s.onended = () => { if (token === this.token && this.src === s) { this.src = null; this.playing = false; this.ended = true; } };
      this.offset = Math.max(0, Math.min(at, this.buf.duration));
      this.start = this.ctx.currentTime; this.src = s;
      s.start(0, this.offset);
    },
    play(path, size, at) {
      this.ensure();
      const token = ++this.token;
      this.playing = true; this.ended = false; this.offset = at;
      if (path === this.path && this.buf) { this.pending = false; this.begin(at); return true; }
      // The track playing so far goes on until the new one is decoded.
      this.pending = true; this.buf = null; this.path = path;
      const bytes = CursedFiles.read(path, 0, size);
      if (!bytes) { this.playing = false; this.ended = true; this.pending = false; this.path = ''; return false; }
      this.ctx.decodeAudioData(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)).then(buf => {
        if (token !== this.token) return;
        this.buf = buf; this.pending = false; this.begin(this.offset);
      }, () => {
        if (token !== this.token) return;
        this.pending = false; this.playing = false; this.ended = true; this.path = '';
      });
      return true;
    },
    seek(at) {
      if (!this.playing) return;
      if (this.pending || !this.buf) { this.offset = at; return; }
      this.token++; this.begin(at);
    },
    stop() { this.token++; this.halt(); this.playing = false; this.pending = false; this.ended = false; },
    position() {
      if (!this.playing) return 0;
      if (this.pending || !this.src) return this.offset;
      return Math.min(this.offset + this.ctx.currentTime - this.start, this.buf.duration);
    },
    // 1 playing, 2 ended since the last call (then cleared).
    poll() { const e = this.ended; this.ended = false; return (this.playing ? 1 : 0) | (e ? 2 : 0); },
    volume(v) { if (this.gain) this.gain.gain.value = v; },
  };
  window.CursedMusic = M;
  return true;
})()
"""

static var _js: JavaScriptObject

var bus := "Music"
var playing := false
var volume_db := 0.0:
	set(v):
		volume_db = v
		_push_volume()
var _path := ""
var _gain := -1.0


static func available() -> bool:
	if _js:
		return true
	if not OS.has_feature("web") or not GameFiles.bridge or not bool(JavaScriptBridge.eval(JS, true)):
		return false
	_js = JavaScriptBridge.get_interface("CursedMusic")
	return _js != null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Starts `path` (a stream/*.mp3 of the browser data) from `at` seconds.
func play_path(path: String, at := 0.0) -> void:
	_path = path
	play(at)


func play(at := 0.0) -> void:
	if _path.is_empty() or not available():
		return
	playing = bool(_js.play(GameFiles.relative(_path), GameFiles.length(_path), at))
	_gain = -1.0
	_push_volume()


func stop() -> void:
	playing = false
	if _js:
		_js.stop()


func seek(at: float) -> void:
	if _js and playing:
		_js.seek(at)


func get_playback_position() -> float:
	return float(_js.position()) if _js and playing else 0.0


func _process(_dt: float) -> void:
	_push_volume()
	if not playing or _js == null:
		return
	var state := int(_js.poll())
	if state & 1 == 0:
		playing = false
		if state & 2:
			finished.emit()


## The player's level through its bus and the master bus, as Godot mixes it.
func _push_volume() -> void:
	if _js == null:
		return
	var i := AudioServer.get_bus_index(bus)
	var g := 0.0
	if i >= 0 and not AudioServer.is_bus_mute(i) and not AudioServer.is_bus_mute(0):
		g = db_to_linear(volume_db + AudioServer.get_bus_volume_db(i) + (AudioServer.get_bus_volume_db(0) if i != 0 else 0.0))
	if absf(g - _gain) > 0.0001:
		_gain = g
		_js.volume(g)


func _exit_tree() -> void:
	stop()
