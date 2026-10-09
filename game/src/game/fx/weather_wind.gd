extends RefCounted
## Optional vegetation wind, sampled from the terrain's pausable clock.
## Adapted from owned renderer R1 Source/weather_wind.h: slow weather spells,
## direction wander and a saturating storm drive. This does not change the
## original weather simulation, precipitation trajectories or water vertices.
const TRAVEL := 0.6375
const MAX_SWAY := 0.04 # Existing cover placement reserves this horizontal radius.
const UNIFORMS := """
uniform vec4 wind_state = vec4(0.70710678, -0.70710678, 0.0, 0.0);
uniform vec4 wind_phases = vec4(0.0);
"""
## Two broad travelling fronts; strength never multiplies elapsed time.
## With state.w in [0,1], the absolute value is <= 1. Small plants need no
## extra high-frequency leaf flutter; trees add that separately.
const SWAY := """
float ei_vegetation_sway(vec2 p, float seed, vec4 state, vec4 phases) {
	float along = dot(p, state.xy);
	float storm = clamp((state.w - 0.1) / 0.9, 0.0, 1.0);
	return (0.32 + 0.06 * storm
		+ (0.18 + 0.03 * storm) * sin(along * 0.78539816 - phases.x + seed * 0.18)
		+ (0.10 + 0.06 * storm) * sin(along * 0.36959914 - phases.y)) / 0.75;
}
"""


static func map_seed(name: String) -> int:
	var h := 0x811c9dc5
	for byte in name.to_utf8_buffer(): h = ((h ^ byte) * 0x01000193) & 0xffffffff
	return h


## Low 32 bits without overflowing GDScript's signed 64-bit multiplication.
static func mul32(a: int, b: int) -> int:
	return (((a & 0xffff) * b) + (((a >> 16) * (b & 0xffff) & 0xffff) << 16)) & 0xffffffff


static func lattice(seed_value: int, cell: int) -> float:
	var h := seed_value ^ mul32(cell & 0xffffffff,0x9e3779b1) ^ mul32((cell >> 32) & 0xffffffff,0x85ebca77)
	h = mul32(h ^ (h >> 16),0x7feb352d)
	h = mul32(h ^ (h >> 15),0x846ca68b)
	h ^= h >> 16
	return float(h >> 8) / 16777216.0


static func noise(seed_value: int, x: float) -> float:
	var cell := floori(x); var f := x - floorf(x)
	var u := f*f*f*(f*(f*6.0-15.0)+10.0)
	return lerpf(lattice(seed_value,cell),lattice(seed_value,cell+1),u)


## Same client cosine fade as precipitation. Sampling either side of
## Weather.tick's endpoint gives the same result; snow is a weaker storm.
static func precipitation(weather: Weather, now: float, mode: int) -> float:
	if weather == null or weather._shown != mode: return 0.0
	if weather._fade <= 0.0: return float(weather._target == mode)
	var f := clampf((now-weather._start)/weather._fade,0.0,1.0)
	var amount := (1.0-cos(f*PI))*0.5
	return amount if weather._target == mode else 1.0-amount


static func sample(seconds: float, seed_value: int, direction: Vector2, force: float,
		rain := 0.0, snow := 0.0, sheltered := false) -> Dictionary:
	var storm := 0.0 if sheltered else clampf(maxf(rain,0.8*snow),0.0,1.0)
	var spell := 0.65*noise(seed_value,seconds/150.0)+0.35*noise(seed_value ^ 0x5bd1e995,seconds/50.0+17.0)
	var windy := smoothstep(0.52,0.78,spell)
	var speed := 0.85+0.6*windy+0.9*storm
	var strength := speed if speed<=1.0 else 1.0+0.25*(1.0-exp(-(speed-1.0)/0.25))
	var gust := clampf(0.1+0.4*windy+0.6*storm,0.0,1.0)
	var f := clampf(force,0.0,1.0)
	if f<0.3: f = 0.15+f*f/0.6
	# Keep the existing 4 cm cover envelope, including storms at force 1.
	var amplitude := minf((0.06+0.5*f)*strength/0.4,1.0)*(0.2 if sheltered else 1.0)
	var along := direction.normalized() if direction.length_squared()>1e-12 else Vector2(1,-1).normalized()
	along = along.rotated((0.2+0.15*storm)*(2.0*noise(seed_value ^ 0xb5297a4d,seconds/80.0+5.0)-1.0))
	return {"state":Vector4(along.x,along.y,amplitude,gust),
		# Wrap each phase separately: wrapping seconds would jump at an hour.
		"phases":Vector4(fposmod(seconds*TRAVEL,TAU),fposmod(seconds*TRAVEL*0.47,TAU),
			fposmod(seconds*0.85,TAU),fposmod(seconds*2.6,TAU))}


static func bind(material: ShaderMaterial, frame: Dictionary) -> void:
	material.set_shader_parameter("wind_state",frame.state)
	material.set_shader_parameter("wind_phases",frame.phases)
