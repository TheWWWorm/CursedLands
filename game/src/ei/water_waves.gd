class_name EIWaterWaves
extends RefCounted
## Native map water state:6c57a0 grid,6c7d30 wind,6cb1a0 tick phase,
##6c3e40 sine-table lookup. Local CRT history is deliberately caller-owned.

const CRT := preload("res://src/ei/crt_random.gd")
const TICK := 0.055
const PI_F32 := 3.1415927410125732
const TAU_F32 := 6.2831854820251465
const AMPLITUDE := 0.30000001192092896
const WIND_SCALE := 0.4487989842891693
const PHASE_STEP := -0.14959967136383057
const WIND_ANGLE := 0.5002501606941223

var ticks := 1
var acc := 0.0
var phase := TAU_F32
var force := 0.0
var amplitude := 0.0
var delta := 0.0
var gradient := Vector2.ZERO
static var _sines: PackedFloat32Array

func _init(strength := 0.4) -> void:
	set_wind(Vector3(0,0,1),strength)

func set_wind(direction: Vector3, strength: float) -> void:
	force = f32(clampf(f32(strength),0.0,1.0))
	amplitude = f32(AMPLITUDE * force)
	delta = f32(PHASE_STEP * force)
	var x := float(direction.x)
	var y := float(direction.y)
	var z := float(direction.z)
	var norm := sqrt(x*x+y*y+z*z)
	if norm != 0.0:
		x = f32(x/norm)
		y = f32(y/norm)
	var factor := PI_F32 * WIND_ANGLE + asin(1.0-force)
	gradient = Vector2(f32(WIND_SCALE*x*factor),f32(WIND_SCALE*y*factor))

func advance(dt: float) -> void:
	acc += dt
	while acc >= TICK:
		acc -= TICK
		ticks += 1
		phase = f32(phase + delta)

func time_ticks() -> float:
	return float(ticks-1) + acc/TICK

static func f32(value: float) -> float:
	return PackedFloat32Array([value])[0]

static func phase_grid(seed_value := 1) -> PackedFloat32Array:
	var g := PackedFloat32Array()
	g.resize(33*33)
	var rng := CRT.new(seed_value)
	for i in 40:
		var cx := float(rng.next_int()%33)
		var cy := float(rng.next_int()%33)
		var radius := float(rng.next_int()%5+1)
		var r2 := radius*radius
		for y in 33:
			for x in 33:
				var d2 := (float(x)-cx)*(float(x)-cx)+(float(y)-cy)*(float(y)-cy)
				if d2 < r2:
					g[y*33+x] += (1.0-d2/r2)*PI_F32*0.5
	for i in range(1,32):
		var a := f32((g[i]+g[1056+i])*0.5)
		g[i] = a
		g[1056+i] = a
		var b := f32((g[i*33]+g[i*33+32])*0.5)
		g[i*33] = b
		g[i*33+32] = b
	var c := f32((g[1056]+g[1088]+g[32]+g[0])*0.25)
	for i in [0,32,1056,1088]:
		g[i] = c
	return g

static func sine_table() -> PackedFloat32Array:
	if _sines.is_empty():
		_sines.resize(512)
		for i in 512:
			_sines[i] = sin(float(i)*PI/256.0)
	return _sines

static func nearest_even(value: float) -> int:
	var lo := floori(value)
	var fraction := value-float(lo)
	return lo if fraction < 0.5 or (fraction == 0.5 and (lo&1) == 0) else lo+1

static func sine(angle: float) -> float:
	return sine_table()[nearest_even(f32(angle*(256.0/PI)))&511]

## One native vertex in EI space; the executable golden supplies the phase
## and base, so no asset/renderer inference is used by the fixture.
func vertex(base: Vector3, cell: Vector2i, kind: int, wave: float,
		phase_value: float, negative_depth := false, horizontal_ticks := -1.0) -> Vector3:
	wave = f32(wave)
	var tau := TAU_F32
	var travelling := f32(fmod(tau + float(base.x)*float(gradient.x)+float(base.y)*float(gradient.y),tau))
	var temporal := f32(fmod(phase*wave,tau))
	var p := f32(travelling+temporal)
	var s := sine(p+f32(phase_value))
	var a := f32(amplitude*wave)
	if kind == 4:
		if negative_depth:
			return Vector3(f32(base.x+s*a),f32(base.y+s*a),base.z)
		return base
	var t := f32((time_ticks() if horizontal_ticks < 0.0 else horizontal_ticks)*f32(0.05))
	return Vector3(f32(base.x+sine(float(cell.x)*f32(0.7853981)+t)*a*3.0),
		f32(base.y+sine(float(cell.y)*f32(0.7853981)+t)*a*3.0),f32(base.z+s*a*0.25))
