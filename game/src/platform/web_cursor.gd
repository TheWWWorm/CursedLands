extends RefCounted
## The game cursor in a browser (GameCursor on the web export).
##
## Godot's custom cursor becomes a CSS `url()` cursor on the canvas. Setting
## a new image for every animation frame (8 a second) makes the browser load
## each one again and show its own arrow meanwhile, and a CSS cursor is in CSS
## pixels: the window-scaled size counted in canvas (device) pixels came out
## devicePixelRatio times too large. Browsers also replace a cursor larger
## than 32 CSS px with their own arrow wherever the image would reach past
## the page (Chromium EventHandler, Firefox likewise): near the right and
## bottom edges, where the HUD is.
##
## So here every frame is sent to the page once and kept, a frame is shown
## only after the browser has decoded it (until then the previous one stays),
## the size is the desktop's in device pixels (an image-set at the page's
## pixel ratio), and next to the page edges the frame at most 32 CSS px is
## shown. The canvas's cursor style stays the engine's: only its arrow
## ("default") is replaced, as Input.set_custom_mouse_cursor does on desktop.

const SMALL_CSS := 32.0   # the largest cursor a browser shows anywhere
const MAX_CSS := 128.0    # larger CSS cursors are ignored altogether

const JS := """
(() => {
  if (window.CursedCursor) return true;
  const canvas = document.getElementById('canvas') || document.querySelector('canvas');
  if (!canvas) return false;
  const style = canvas.style, frames = new Map();
  let want = null, shown = null, engine = '', mx = -1e6, my = -1e6;
  const prefix = (window.CSS && CSS.supports('cursor', 'image-set(url("a.png") 2x) 0 0, auto')) ? 'image-set'
    : (window.CSS && CSS.supports('cursor', '-webkit-image-set(url("a.png") 2x) 0 0, auto')) ? '-webkit-image-set' : '';
  const engineArrow = () => engine === '' || engine === 'default' || engine === 'auto';
  function variant(v) {
    // A cursor larger than 32 CSS px that would reach outside the page is
    // replaced by the browser's arrow: use the small one there.
    if (!v.small || (mx - v.big.x >= 0 && my - v.big.y >= 0 &&
        mx - v.big.x + v.big.w <= innerWidth && my - v.big.y + v.big.h <= innerHeight)) return v.big;
    return v.small;
  }
  function apply() {
    if (want === null || !engineArrow()) return;
    const v = frames.get(want);
    if (!v) return;
    const c = variant(v);
    if (!c.ready || c === shown) return;   // not decoded yet: keep the last frame
    shown = c;
    style.setProperty('cursor', c.css);
  }
  function make(png, res, x, y, w, h) {
    const bin = atob(png), bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    const url = URL.createObjectURL(new Blob([bytes], {type: 'image/png'}));
    const c = {url, x, y, w, h, ready: false,
      css: (res !== 1 && prefix ? prefix + '(url("' + url + '") ' + res + 'x)' : 'url("' + url + '")') + ' ' + x + ' ' + y + ', default'};
    const img = new Image();
    img.onload = () => { c.ready = true; apply(); };
    img.src = url;
    return c;
  }
  Object.defineProperty(style, 'cursor', {configurable: true,
    get() { return style.getPropertyValue('cursor'); },
    set(value) {
      engine = String(value); shown = null;
      if (want !== null && engineArrow()) apply();
      else style.setProperty('cursor', engine);
    }});
  addEventListener('pointermove', e => {
    mx = e.clientX; my = e.clientY;
    if (want !== null && frames.has(want) && frames.get(want).small) apply();
  }, {passive: true, capture: true});
  window.CursedCursor = {
    imageSet: () => prefix !== '',
    has: key => frames.has(key),
    add(key, png, res, x, y, w, h, spng, sx, sy, sw, sh) {
      if (frames.has(key)) return;
      frames.set(key, {big: make(png, res, x, y, w, h), small: spng ? make(spng, res, sx, sy, sw, sh) : null});
    },
    show(key) { want = key; apply(); },
    off() { want = null; shown = null; style.setProperty('cursor', engine); },
    clear() {
      want = null; shown = null;
      style.setProperty('cursor', engine);
      for (const v of frames.values()) for (const c of [v.big, v.small]) if (c) URL.revokeObjectURL(c.url);
      frames.clear();
    },
  };
  return true;
})()
"""

static var _js: JavaScriptObject
static var _image_set := false
static var _sent := {}


static func available() -> bool:
	if _js:
		return true
	if not OS.has_feature("web") or not bool(JavaScriptBridge.eval(JS, true)):
		return false
	_js = JavaScriptBridge.get_interface("CursedCursor")
	if _js:
		_image_set = bool(_js.imageSet())
	return _js != null


## Shows frame `frame` of cursor strip `kind` at `px` device pixels a side
## (GameCursor.size_px), hot spot `hs` in those pixels.
static func show(kind: String, frame: int, px: int, hs: Vector2) -> void:
	if not available():
		return
	var dpr := maxf(float(JavaScriptBridge.eval("window.devicePixelRatio || 1", true)), 0.25)
	px = mini(px, int(MAX_CSS * dpr))
	var key := "%s#%d@%d/%d" % [kind, frame, px, roundi(dpr * 100.0)]
	if not _sent.has(key):
		var big := _variant(kind, frame, px, hs, dpr)
		if big.is_empty():
			return
		var small := []
		if px > SMALL_CSS * dpr:
			var spx := int(SMALL_CSS * dpr)
			small = _variant(kind, frame, spx, hs * (float(spx) / px), dpr)
		if small.is_empty():
			small = ["", 0, 0, 0, 0]
		_js.add(key, big[0], dpr if _image_set else 1.0, big[1], big[2], big[3], big[4],
			small[0], small[1], small[2], small[3], small[4])
		_sent[key] = true
	_js.show(key)


## [png base64, hot spot x, y, width, height] in CSS px.
static func _variant(kind: String, frame: int, px: int, hs: Vector2, dpr: float) -> Array:
	var css := roundi(px / dpr)
	# Without image-set the browser draws the image 1:1 in CSS px.
	var f: Array = load("res://src/ui/game_cursor.gd").scaled(kind, px if _image_set else css)
	if f.is_empty():
		return []
	var img: Image = f[frame % f.size()]
	var h := (hs / dpr).round().clamp(Vector2.ZERO, Vector2(css - 1, css - 1))
	return [Marshalls.raw_to_base64(img.save_png_to_buffer()), int(h.x), int(h.y), css, css]


## Back to the engine's own cursor (GameCursor with no kind).
static func off() -> void:
	if _js:
		_js.off()


static func clear() -> void:
	if _js:
		_js.clear()
	_sent.clear()
