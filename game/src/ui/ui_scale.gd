class_name UiScale
## The interface scale rules in one place.
##
## The authored interface is an 800×600 frame; every screen scales that frame
## into the room it has. Screens used to restate the ratio with their own
## formula; they now name the rule they follow, so one fix reaches all of
## them and the registry lint (tools/tests/test_ui_conventions.py) refuses a
## new private formula.

const WIDTH := 800.0
const HEIGHT := 600.0
## Font sizes as fractions of the 800-wide frame: small, normal, large.
const FONT_EM := [0.01733, 0.01867, 0.024]
## Smallest raster the original fonts stay legible at.
const MIN_FONT_PX := 6


## Scale from the room's height alone: strips pinned to an edge whose width
## follows the content (HUD strips, the travel map, the game-over notice).
static func by_height(size: Vector2) -> float:
	return maxf(size.y, 1.0) / HEIGHT


## Scale from the room's width against an authored frame width.
static func by_width(size: Vector2, frame_width: float = WIDTH) -> float:
	return maxf(size.x, 1.0) / frame_width


## Scale that keeps the whole 800×600 frame inside the room (boards and
## panels that must stay complete on a narrow or short window).
static func fit(size: Vector2) -> float:
	return fit_frame(size, WIDTH, HEIGHT)


## Scale that keeps a frame of another authored size inside the room.
static func fit_frame(size: Vector2, frame_width: float, frame_height: float) -> float:
	return minf(maxf(size.x, 1.0) / frame_width, maxf(size.y, 1.0) / frame_height)


## Scale from the room's shorter side against the frame height: overlays
## drawn around world positions, which must not grow with a wide window.
static func by_min_side(size: Vector2) -> float:
	return maxf(minf(size.x, size.y), 1.0) / HEIGHT


## Height scale, narrowed on portrait rooms so a strip `frame_width` wide at
## scale 1 still fits across (HUD top strip, message log).
static func by_height_within(size: Vector2, frame_width: float) -> float:
	var k := by_height(size)
	return minf(k, size.x / frame_width) if size.x < size.y else k


## Height scale of the canvas a HUD control draws on (its layer's `ui_size`
## when it has one, else the viewport).
static func canvas_height(control: CanvasItem) -> float:
	return Interface800.canvas_size(control).y / HEIGHT


## Pixel font size for a scale `k` and a FONT_EM slot.
static func font_px(k: float, slot: int, floor: int = MIN_FONT_PX) -> int:
	return maxi(floor, int(round(WIDTH * k * FONT_EM[slot])))


## Pixel font size for a drawing width (a canvas or viewport width).
static func font_px_for_width(width: float, slot: int, floor: int = MIN_FONT_PX) -> int:
	return maxi(floor, int(round(width * FONT_EM[slot])))


## Surface scale for the settings-style dialogs (SettingsDialog, ModPanel,
## DifficultyPanel): a 1248×768 surface scaled up to 3× by oversampling.
static func dialog(safe_size: Vector2) -> float:
	return clampf(minf(safe_size.x / 1248.0, safe_size.y / 768.0), 1.0, 3.0)


## Reading scale for the encyclopedia: 900 px of height reads at 1×, a short
## window may shrink to 0.85×, a 4K window grows to 3×.
static func reading(available_height: float) -> float:
	return clampf(available_height / 900.0, 0.85, 3.0)
