class_name PadGyro
extends RefCounted
## Controller angular velocity, or the handheld's built-in sensor on Android.
## Godot already rotates the handheld sensor into screen axes. SDL controllers
## use pitch / yaw / roll axes. Both report radians per second, not an angle.
## Only read while a pad pointer is usable; calibration needs a still device.

const NONE := -2
const HANDHELD := -1
const CALIBRATION_SEC := 1.5
const STILL_RATE := 0.15
const NOISE_RATE := 0.008

var source := NONE
var rate := Vector3.ZERO
var calibrating := false
var calibration_ok := false
var _remaining := 0.0
var _force := false
var _sum := Vector3.ZERO
var _still_sec := 0.0
var _bias := {}
var _calibrated := {}


func _handheld() -> bool:
	return Portability.handheld()


func _source(device: int) -> int:
	if device >= 0 and Input.has_joy_motion_sensors(device):
		return device
	return HANDHELD if _handheld() else NONE


func _enable(dev: int, on: bool) -> void:
	if dev >= 0:
		Input.set_joy_motion_sensors_enabled(dev, on)


func _read(dev: int) -> Vector3:
	return Input.get_joy_gyroscope(dev) if dev >= 0 else Input.get_gyroscope()


func _native_calibration(dev: int, on: bool) -> void:
	if dev >= 0:
		if on:
			Input.start_joy_motion_sensors_calibration(dev)
		else:
			Input.stop_joy_motion_sensors_calibration(dev)


func _select(dev: int) -> void:
	if source == dev:
		return
	stop()
	source = dev
	if source != NONE:
		_enable(source, true)


func _begin() -> void:
	calibrating = true
	calibration_ok = false
	_remaining = CALIBRATION_SEC
	_sum = Vector3.ZERO
	_still_sec = 0.0
	rate = Vector3.ZERO
	_native_calibration(source, true)


func calibrate(device: int) -> bool:
	var dev := _source(device)
	if dev == NONE:
		calibration_ok = false
		return false
	_select(dev)
	if calibrating:
		_native_calibration(source, false)
	_force = true
	_begin()
	return true


func stop() -> void:
	if source != NONE:
		if calibrating:
			_native_calibration(source, false)
		_enable(source, false)
	source = NONE
	rate = Vector3.ZERO
	calibrating = false
	_force = false


func update(device: int, wanted: bool, dt: float) -> void:
	rate = Vector3.ZERO
	var dev := _source(device) if wanted else NONE
	# An explicit calibration also works from the Options page before ✓.
	if _force:
		dev = source
	_select(dev)
	if source == NONE:
		return
	if not _calibrated.has(source) and not calibrating:
		_begin()
	var raw := _read(source)
	if not raw.is_finite():
		if calibrating:
			_remaining -= dt
			if _remaining <= 0.0:
				_native_calibration(source, false)
				calibrating = false
				_force = false
		return
	if calibrating:
		_remaining -= dt
		if raw.length() < STILL_RATE:
			_sum += raw * dt
			_still_sec += dt
		if _remaining <= 0.0:
			_native_calibration(source, false)
			calibration_ok = _still_sec >= CALIBRATION_SEC * 0.5
			if calibration_ok:
				if source == HANDHELD:
					_bias[source] = _sum / _still_sec
				_calibrated[source] = true
			calibrating = false
			_force = false
		return
	if not wanted:
		return
	rate = raw - Vector3(_bias.get(source, Vector3.ZERO))
	if Vector2(rate.x, rate.y).length() < NOISE_RATE:
		rate = Vector3.ZERO


## Pointer displacement is independent of frame rate and simulation speed.
func delta(dt: float, height: float, sensitivity: float) -> Vector2:
	if not rate.is_finite() or dt <= 0.0:
		return Vector2.ZERO
	var gain := height * pow(2.0, (sensitivity - 50.0) / 25.0)
	return Vector2(-rate.y, -rate.x) * gain * minf(dt, 0.1)
